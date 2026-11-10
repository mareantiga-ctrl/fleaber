/// REDTEAM_BLIND_BM_CHAT_POS_BFBK_v1 — pass1. Staging only. No fixes.
import 'dart:convert';
import 'dart:io';

import '_rtbm.dart';

Future<void> main() async {
  final c = Rtbm.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  final sku = await c.createProduct(title: '$prefix-mbway', price: 12);
  if (sku == null) {
    stderr.writeln('no sku');
    exit(4);
  }
  final chatId = await c.ensureChat(sku);
  final oid = await c.insertOrder(
    productId: sku,
    jwt: c.buyerJwt,
    price: 12,
    payment: 'MB WAY',
  );
  if (chatId == null || oid == null) {
    stderr.writeln('no chat/order ${c.notes}');
    exit(4);
  }
  final paid = await c.payToPago();
  if (paid == null) {
    stderr.writeln('setup_paid_order failed');
    exit(4);
  }
  final paidTotal = (paid.paidCents / 100).toStringAsFixed(2);

  Future<void> tryPlain({
    required String id,
    required String lens,
    required String text,
    required bool expectBlock,
    bool countIfPersist = true,
    String? jwt,
    String? chat,
  }) async {
    final h = await c.postMsg(
      chatId: chat ?? chatId,
      text: text,
      jwt: jwt ?? c.buyerJwt,
    );
    final persisted = h.ok && h.firstId != null;
    if (persisted && h.firstId != null) c.createdMsgIds.add(h.firstId!);
    if (expectBlock) {
      if (persisted) {
        if (countIfPersist) {
          c.hold(
            id: id,
            lens: lens,
            severity: 'P2',
            title: 'Texto de pagamento persistiu: $text',
            actor: 'buyer JWT',
            pre: 'denylist BFBK sem este rail/encoding',
            repro: 'POST chat_messages text=$text',
            expected: 'recusa payment_lie / inbox',
            obtained: h.brief,
            evidence: {'text': text, 'id': h.firstId},
          );
        } else {
          c.note(id, 'persistiu (exacto BFBK, não contar)', h.brief, lens: lens);
        }
      } else {
        c.block(id, lens, 'recusado', h.brief);
      }
    } else {
      c.note(id, persisted ? 'persistiu' : 'recusado', h.brief, lens: lens);
    }
  }

  Future<Map<String, dynamic>?> tryCard({
    required String id,
    required String lens,
    required Map<String, Object?> payload,
    String? jwt,
    String? chat,
    bool countIfPersist = true,
    String severity = 'P1',
    String title = '',
  }) async {
    final text = jsonCard(payload);
    final h = await c.postMsg(
      chatId: chat ?? chatId,
      text: text,
      jwt: jwt ?? c.buyerJwt,
    );
    final persisted = h.ok && h.firstId != null;
    if (persisted && h.firstId != null) c.createdMsgIds.add(h.firstId!);
    if (persisted) {
      if (countIfPersist) {
        c.hold(
          id: id,
          lens: lens,
          severity: severity,
          title: title.isEmpty ? 'card persistiu ${payload['kind']}' : title,
          actor: 'buyer JWT',
          pre: 'order $oid chat $chatId',
          repro: 'POST FLEABER_JSON_V1 ${jsonEncode(payload)}',
          expected: 'recusa notes/label/url',
          obtained: h.brief,
          evidence: {
            'msg_id': h.firstId,
            'payload': payload,
            'stored': (await c.msgRow(h.firstId!))?['text'],
          },
        );
      } else {
        c.note(id, 'persistiu (não contar)', h.brief, lens: lens);
      }
    } else {
      c.block(id, lens, title.isEmpty ? 'card recusado' : title, h.brief);
    }
    return persisted ? await c.msgRow(h.firstId!) : null;
  }

  // ---- BM1 cards: rails novos (não Affirm/Cash App exactos) ----
  await tryCard(
    id: 'BM1.clearpay-notes',
    lens: 'BM1',
    title: 'notes Clearpay no card reservation_payment_submitted',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'Clearpay confirmado 12,00 €',
    },
  );
  await tryCard(
    id: 'BM1.shoppay-notes',
    lens: 'BM1',
    title: 'notes Shop Pay no card reservation_payment_submitted',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'Shop Pay 12,00 € aprovado',
    },
  );
  await tryCard(
    id: 'BM1.strike-notes',
    lens: 'BM1',
    title: 'notes Strike no card reservation_payment_submitted',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'Strike 12,00 € pago',
    },
  );
  await tryCard(
    id: 'BM1.zelle-notes',
    lens: 'BM1',
    title: 'notes Zelle no card reservation_payment_submitted',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'Zelle 12,00 € received',
    },
  );

  // exactos BFBK — não contar
  await tryCard(
    id: 'BM1.affirm-label-control',
    lens: 'BM1',
    countIfPersist: false,
    payload: {
      'kind': 'seguro_fleaber_paid',
      'order_id': paid.oid,
      'total': paidTotal,
      'label': 'Affirm 12,00 €',
    },
    chat: paid.chatId,
  );
  await tryCard(
    id: 'BM1.cashapp-notes-control',
    lens: 'BM1',
    countIfPersist: false,
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'Cash App Pay 12,00 €',
    },
  );

  await tryCard(
    id: 'BM1.clearpay-seguro-label',
    lens: 'BM1',
    severity: 'P2',
    title: 'label Clearpay + montante 999 no card seguro (order Stripe)',
    chat: paid.chatId,
    payload: {
      'kind': 'seguro_fleaber_paid',
      'order_id': paid.oid,
      'total': paidTotal,
      'label': 'Clearpay 999,00 €',
    },
  );
  await tryCard(
    id: 'BM1.shoppay-seguro-label',
    lens: 'BM1',
    severity: 'P2',
    title: 'label Shop Pay no card seguro',
    chat: paid.chatId,
    payload: {
      'kind': 'seguro_fleaber_paid',
      'order_id': paid.oid,
      'total': paidTotal,
      'label': 'Shop Pay',
    },
  );

  // ---- BM2 encoding novos (não greek Affirm exacto) ----
  const lunateSigma = '\u03F9'; // Ϲ
  const cyrDze = '\u0405'; // Ѕ
  const greekRho = '\u03A1'; // Ρ
  await tryCard(
    id: 'BM2.clearpay-lunate',
    lens: 'BM2',
    title: 'notes Ϲlearpay (lunate sigma) no card prova',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': '${lunateSigma}learpay confirmado 12,00 €',
    },
  );
  await tryCard(
    id: 'BM2.shoppay-cyr-s',
    lens: 'BM2',
    title: 'notes Ѕhop Pay (cyrillic Dze)',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': '${cyrDze}hop Pay 12,00 €',
    },
  );
  await tryCard(
    id: 'BM2.strike-zwsp',
    lens: 'BM2',
    title: 'notes St\\u200brike (ZWSP)',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'St\u200brike 12,00 € confirmado',
    },
  );
  await tryCard(
    id: 'BM2.clearpay-fullwidth',
    lens: 'BM2',
    title: 'notes Clearpay fullwidth',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'Ｃｌｅａｒｐａｙ 12,00 €',
    },
  );
  await tryPlain(
    id: 'BM2.plain-clearpay',
    lens: 'BM2',
    text: 'Clearpay confirmado 12,00 €',
    expectBlock: true,
  );
  await tryPlain(
    id: 'BM2.plain-shoppay',
    lens: 'BM2',
    text: 'Shop Pay 12,00 € aprovado',
    expectBlock: true,
  );
  await tryPlain(
    id: 'BM2.plain-strike-rho',
    lens: 'BM2',
    text: 'St${greekRho}ike 12,00 €',
    expectBlock: true,
  );
  // control exact Affirm greek — não contar
  await tryPlain(
    id: 'BM2.affirm-greek-control',
    lens: 'BM2',
    text: '\u0391ffirm 12,00 €',
    expectBlock: true,
    countIfPersist: false,
  );

  // ---- BM3 cronologia ----
  final past = DateTime.now().toUtc().subtract(const Duration(days: 40));
  final pastHit = await c.postMsg(
    chatId: chatId,
    text: 'BM3 backdate ping',
    createdAt: past.toIso8601String(),
  );
  if (pastHit.ok && pastHit.firstId != null) {
    c.createdMsgIds.add(pastHit.firstId!);
    final row = await c.msgRow(pastHit.firstId!);
    final stored = DateTime.tryParse('${row?['created_at']}');
    final drifted = stored != null &&
        stored.isBefore(DateTime.now().toUtc().subtract(const Duration(days: 1)));
    if (drifted) {
      c.hold(
        id: 'BM3.insert-created-at-past',
        lens: 'BM3',
        severity: 'P2',
        title: 'INSERT created_at no passado persistiu',
        actor: 'buyer JWT',
        pre: 'trigger guarda created_at := now()',
        repro: 'POST chat_messages created_at=${past.toIso8601String()}',
        expected: 'created_at ≈ now()',
        obtained: row?['created_at'],
        evidence: {'row': row},
      );
    } else {
      c.block('BM3.insert-created-at-past', 'BM3', 'created_at forçado a now',
          row?['created_at']);
    }
  } else {
    c.block('BM3.insert-created-at-past', 'BM3', 'insert recusado', pastHit.brief);
  }

  if (pastHit.firstId != null) {
    final patchAt = await c.rest(
      'PATCH',
      'chat_messages?id=eq.${pastHit.firstId}',
      jwt: c.buyerJwt,
      body: {'created_at': '2020-01-01T00:00:00Z'},
    );
    final after = await c.msgRow(pastHit.firstId!);
    final stored = DateTime.tryParse('${after?['created_at']}');
    final is2020 = stored != null && stored.year == 2020;
    if (patchAt.ok && is2020) {
      c.hold(
        id: 'BM3.patch-created-at',
        lens: 'BM3',
        severity: 'P1',
        title: 'PATCH created_at reescreve cronologia',
        actor: 'buyer JWT',
        pre: 'mensagem própria',
        repro: 'PATCH chat_messages created_at=2020-01-01',
        expected: 'created_at imutável',
        obtained: after?['created_at'],
        evidence: {'patch': patchAt.brief, 'row': after},
      );
    } else {
      c.block('BM3.patch-created-at', 'BM3', 'created_at imutável', {
        'patch': patchAt.brief,
        'stored': after?['created_at'],
      });
    }
  }

  final jsonDel = await c.postMsg(
    chatId: chatId,
    text: jsonCard({
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
    }),
  );
  if (jsonDel.ok && jsonDel.firstId != null) {
    final del = await c.rest(
      'DELETE',
      'chat_messages?id=eq.${jsonDel.firstId}',
      jwt: c.buyerJwt,
    );
    final still = await c.msgRow(jsonDel.firstId!);
    if (del.ok && still == null) {
      c.hold(
        id: 'BM3.delete-json-card',
        lens: 'BM3',
        severity: 'P1',
        title: 'DELETE apaga card JSON de prova',
        actor: 'buyer JWT',
        pre: 'card reservation_payment_submitted',
        repro: 'DELETE chat_messages?id=eq.{id}',
        expected: 'chat_system_card_immutable',
        obtained: del.brief,
      );
    } else {
      c.block('BM3.delete-json-card', 'BM3', 'DELETE card recusado', del.brief);
    }
  }

  final plainDel = await c.postMsg(chatId: chatId, text: 'apaga-me BM3');
  if (plainDel.ok && plainDel.firstId != null) {
    final del = await c.rest(
      'DELETE',
      'chat_messages?id=eq.${plainDel.firstId}',
      jwt: c.buyerJwt,
    );
    c.note('BM3.delete-plain', del.ok ? 'plain delete ok' : 'delete recusado',
        del.brief,
        lens: 'BM3');
  }

  // ---- BM4 URLs ----
  String proofPath(String extra) =>
      '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oid/$extra';

  await tryCard(
    id: 'BM4.dotdot-traversal',
    lens: 'BM4',
    title: 'proof_url com ../ foge do prefixo order_proofs',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oid/../../../public/rtbm-stolen.jpg',
    },
  );
  await tryCard(
    id: 'BM4.dotdot-encoded',
    lens: 'BM4',
    title: 'proof_url %2e%2e path traversal',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oid/%2e%2e/%2e%2e/%2e%2e/public/x.jpg',
    },
  );
  await tryCard(
    id: 'BM4.fragment-needle',
    lens: 'BM4',
    title: 'needle só no fragmento # (controlo BFBK path-only)',
    countIfPersist: false,
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/chat_uploads/${c.buyerId}/x.jpg#order_proofs/${c.buyerId}/$oid/',
    },
  );
  await tryCard(
    id: 'BM4.query-needle-control',
    lens: 'BM4',
    title: 'needle só na query (exacto BFBK, não contar)',
    countIfPersist: false,
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/chat_uploads/${c.buyerId}/x.jpg?order_proofs=${c.buyerId}/$oid/',
    },
  );
  await tryCard(
    id: 'BM4.signed-other-bucket',
    lens: 'BM4',
    title: 'signed URL noutro bucket com needle no path',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/sign/avatars/order_proofs/${c.buyerId}/$oid/x.jpg',
    },
  );
  await tryCard(
    id: 'BM4.compact-uuid-path',
    lens: 'BM4',
    title: 'proof_url buyer/order compactos (sem hífen)',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${compactUuid(c.buyerId!)}/${compactUuid(oid)}/x.jpg',
    },
  );
  await tryCard(
    id: 'BM4.prefix-before-needle',
    lens: 'BM4',
    title: 'path com prefixo extra antes de order_proofs',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/other/${c.buyerId}/order_proofs/${c.buyerId}/$oid/x.jpg',
    },
  );
  await tryCard(
    id: 'BM4.honest-path',
    lens: 'BM4',
    countIfPersist: false,
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url': proofPath('rtbm.jpg'),
    },
  );

  // ---- BM5 inbox ----
  Future<void> tryInbox(String id, String text, {bool count = true}) async {
    final h = await c.rest(
      'PATCH',
      'chats?id=eq.$chatId',
      jwt: c.buyerJwt,
      body: {'last_message': text},
    );
    final row = await c.chatRow(chatId);
    final stored = '${row?['last_message']}';
    if (h.ok && stored == text) {
      if (count) {
        c.hold(
          id: id,
          lens: 'BM5',
          severity: 'P1',
          title: 'inbox last_message forjado: $text',
          actor: 'buyer JWT',
          pre: 'chats_update_participants',
          repro: 'PATCH chats.last_message=$text',
          expected: 'chat_inbox_preview_forbidden',
          obtained: stored,
        );
      } else {
        c.note(id, 'inbox persistiu (exacto, não contar)', stored, lens: 'BM5');
      }
    } else {
      c.block(id, 'BM5', 'inbox recusado', {'http': h.brief, 'stored': stored});
    }
  }

  await tryInbox('BM5.inbox-clearpay', 'Clearpay confirmado 12,00 €');
  await tryInbox('BM5.inbox-shoppay', 'Shop Pay 12 € aprovado');
  await tryInbox('BM5.inbox-strike', 'Strike 12,00 €');
  await tryInbox('BM5.inbox-affirm-control', 'Affirm settled 12,00 €', count: false);

  // ---- BM6 storage ----
  final objectPath =
      'order_proofs/${c.buyerId}/$oid/rtbm_list.bin';
  final up = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$objectPath',
    jwt: c.buyerJwt,
    rawBytes: utf8.encode('rtbm-proof'),
    extra: {'x-upsert': 'true'},
  );
  c.note('BM6.upload-own', 'upload próprio', up.brief, lens: 'BM6');

  final listRoot = await c.req(
    'POST',
    '/storage/v1/object/list/fleaber_private',
    jwt: c.buyer2Jwt,
    body: {'prefix': 'order_proofs/', 'limit': 20},
  );
  final listB1 = await c.req(
    'POST',
    '/storage/v1/object/list/fleaber_private',
    jwt: c.buyer2Jwt,
    body: {'prefix': 'order_proofs/${c.buyerId}/', 'limit': 20},
  );
  final sawB1 = '${listRoot.body}${listB1.body}'.contains(c.buyerId!) ||
      '${listRoot.body}${listB1.body}'.contains('rtbm_list');
  if (listRoot.ok && sawB1) {
    c.hold(
      id: 'BM6.list-cross-user',
      lens: 'BM6',
      severity: 'P1',
      title: 'B2 lista order_proofs de B1',
      actor: 'buyer2 JWT',
      pre: 'ficheiro B1 em order_proofs/{B1}/{order}/',
      repro: 'POST /storage/v1/object/list/fleaber_private prefix=order_proofs/',
      expected: 'lista vazia / 403',
      obtained: {'root': listRoot.brief, 'b1': listB1.brief},
    );
  } else {
    c.block('BM6.list-cross-user', 'BM6', 'list cross-user recusado', {
      'root': listRoot.brief,
      'b1': listB1.brief,
    });
  }

  final getB1 = await c.req(
    'GET',
    '/storage/v1/object/authenticated/fleaber_private/$objectPath',
    jwt: c.buyer2Jwt,
  );
  if (getB1.ok && getB1.body.contains('rtbm-proof')) {
    c.hold(
      id: 'BM6.get-cross-user',
      lens: 'BM6',
      severity: 'P1',
      title: 'B2 lê prova de B1',
      actor: 'buyer2 JWT',
      pre: 'object order_proofs/B1/…',
      repro: 'GET authenticated fleaber_private/order_proofs/{B1}/…',
      expected: '403',
      obtained: getB1.brief,
    );
  } else {
    c.block('BM6.get-cross-user', 'BM6', 'GET cross-user recusado', getB1.brief);
  }

  final upB2 = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$objectPath',
    jwt: c.buyer2Jwt,
    rawBytes: utf8.encode('stolen'),
    extra: {'x-upsert': 'true'},
  );
  if (upB2.ok) {
    c.hold(
      id: 'BM6.upload-cross-user',
      lens: 'BM6',
      severity: 'P1',
      title: 'B2 faz upload no prefixo order_proofs de B1',
      actor: 'buyer2 JWT',
      pre: 'policy insert_own',
      repro: 'POST storage object order_proofs/{B1}/{order}/rtbm_list.bin',
      expected: '403',
      obtained: upB2.brief,
    );
  } else {
    c.block('BM6.upload-cross-user', 'BM6', 'upload B2 recusado', upB2.brief);
  }

  // ---- BM7 cross-user + meta extra ----
  final b2OnB1 = await c.postMsg(
    chatId: chatId,
    text: 'B2 no chat B1',
    jwt: c.buyer2Jwt,
    sender: c.buyer2Id,
  );
  if (b2OnB1.ok) {
    c.hold(
      id: 'BM7.b2-insert-b1-chat',
      lens: 'BM7',
      severity: 'P1',
      title: 'B2 escreve no chat B1–seller',
      actor: 'buyer2 JWT',
      pre: 'B2 não é participante',
      repro: 'POST chat_messages chat_id=B1',
      expected: '403',
      obtained: b2OnB1.brief,
    );
  } else {
    c.block('BM7.b2-insert-b1-chat', 'BM7', 'B2 fora do chat', b2OnB1.brief);
  }

  await tryCard(
    id: 'BM7.meta-extra-clearpay',
    lens: 'BM7',
    severity: 'P3',
    title: 'chave meta extra com mentira Clearpay persistiu no card',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'meta': {
        'rail': 'Clearpay',
        'amount': '12.00',
        'status': 'paid',
      },
    },
  );

  // ---- BM8 OCR Edge ----
  final liveHit = await c.rest('POST', 'lives', service: true, body: {
    'seller_id': c.sellerId,
    'title': '$prefix-ocr',
    'status': 'live',
    'is_active': true,
  });
  final liveId = liveHit.firstId;
  c.note('BM8.live', 'live fixture', liveHit.brief, lens: 'BM8');

  final fakeTok = await c.edge(
    'ingest-ocr-reservation',
    {
      'live_id': liveId ?? '00000000-0000-0000-0000-000000000000',
      'ocr_line_hash': 'rtbmhash12345678',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'ocr_raw_line': 'Clearpay paid 12 EUR ref A1',
      'ref_number': 1,
    },
    jwt: c.buyerJwt,
    extra: {'x-device-token': 'rtbm-fake-token-clearpay'},
  );
  if (fakeTok.ok) {
    c.hold(
      id: 'BM8.ocr-fake-token',
      lens: 'BM8',
      severity: 'P1',
      title: 'OCR Edge aceita device token falso',
      actor: 'buyer JWT + x-device-token falso',
      pre: 'sem pairing',
      repro: 'POST ingest-ocr-reservation x-device-token=rtbm-fake',
      expected: '401 invalid_token',
      obtained: fakeTok.brief,
    );
  } else {
    c.block('BM8.ocr-fake-token', 'BM8', 'token falso recusado', fakeTok.brief);
  }

  final rpcOcr = await c.rpc(
    'batata_ingest_ocr_reservation_v2',
    {
      'p_device_token': 'rtbm-fake',
      'p_live_id': liveId,
      'p_external_display_name': 'Clearpay',
      'p_external_buyer_ref': 'x',
      'p_ocr_raw_line': 'Clearpay 12,00 €',
      'p_ocr_line_hash': 'rtbmhash12345678',
      'p_detected_at': DateTime.now().toUtc().toIso8601String(),
      'p_requested_qty': 1,
    },
    jwt: c.buyerJwt,
  );
  if (rpcOcr.ok && (rpcOcr.map?['ok'] == true)) {
    c.hold(
      id: 'BM8.ocr-rpc-jwt',
      lens: 'BM8',
      severity: 'P1',
      title: 'JWT chama ingest OCR v2 com token falso',
      actor: 'buyer JWT',
      pre: 'RPC SECURITY DEFINER',
      repro: 'POST rpc/batata_ingest_ocr_reservation_v2',
      expected: '403 / invalid_token',
      obtained: rpcOcr.brief,
    );
  } else {
    c.block('BM8.ocr-rpc-jwt', 'BM8', 'RPC OCR JWT recusado', rpcOcr.brief);
  }

  final out = {
    'auditor': 'REDTEAM_BLIND_BM_CHAT_POS_BFBK_v1',
    'stamp': stamp,
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
    'lenses': c.lensesHit.toList()..sort(),
    'fixtures': {
      'sku': sku,
      'chat': chatId,
      'mbway_order': oid,
      'paid_order': paid.oid,
      'paid_cents': paid.paidCents,
      'paid_chat': paid.chatId,
      'live': liveId,
    },
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
  };
  await dumpJson('${outDir()}/pass1.json', out);
  stdout.writeln('FINDINGS=${c.findings.length} BLOCKED=${c.blocked.length} LENSES=${c.lensesHit}');
}
