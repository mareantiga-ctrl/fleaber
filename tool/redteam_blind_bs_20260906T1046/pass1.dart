/// REDTEAM_BLIND_BS_CHAT_POS_BLBQ_v1 — pass1. Staging only. No fixes.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '_rtbs.dart';

Future<void> main() async {
  final c = Rtbs.fromEnv(loadEnv());
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
  final paid2 = await c.payToPago();
  if (paid2 == null) {
    stderr.writeln('setup_paid_order 2 failed');
    exit(4);
  }
  final paidTotal = (paid.paidCents / 100).toStringAsFixed(2);

  Future<Map<String, dynamic>?> tryCard({
    required String id,
    required String lens,
    required Map<String, Object?> payload,
    String? title,
    String severity = 'P1',
    bool countIfPersist = true,
    String? jwt,
    String? chat,
    String? sender,
  }) async {
    final h = await c.postMsg(
      chatId: chat ?? chatId,
      text: jsonCard(payload),
      jwt: jwt ?? c.buyerJwt,
      sender: sender,
    );
    final persisted = h.ok && h.firstId != null;
    if (persisted && h.firstId != null) c.createdMsgIds.add(h.firstId!);
    if (persisted) {
      if (countIfPersist) {
        c.hold(
          id: id,
          lens: lens,
          severity: severity,
          title: title ?? 'card persistiu ${payload['kind']}',
          actor: 'buyer JWT',
          pre: 'denylist BLBQ sem este rail/encoding/URL',
          repro: 'POST chat_messages FLEABER_JSON_V1:${jsonEncode(payload)}',
          expected: 'chat_system_card_notes_forbidden / url_denied / label_mismatch',
          obtained: h.brief,
          evidence: {'id': h.firstId, 'kind': payload['kind'], 'payload': payload},
        );
      } else {
        c.note(id, 'persistiu (exacto/controlo, não contar)', h.brief, lens: lens);
      }
    } else {
      c.block(id, lens, 'recusado', h.brief);
    }
    return persisted ? h.map : null;
  }

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
          lens: 'BS5',
          severity: 'P1',
          title: 'inbox last_message forjado: $text',
          actor: 'buyer JWT',
          pre: 'chats_update_participants',
          repro: 'PATCH chats.last_message=$text',
          expected: 'chat_inbox_preview_forbidden',
          obtained: stored,
        );
      } else {
        c.note(id, 'inbox persistiu (exacto, não contar)', stored, lens: 'BS5');
      }
    } else {
      c.block(id, 'BS5', 'inbox recusado', {'http': h.brief, 'stored': stored});
    }
  }

  // ---- BS1 cards · rails novos ----
  const newRails = <String, String>{
    'payoneer': 'Payoneer 12,00 €',
    'wu': 'Western Union 12,00 €',
    'interac': 'Interac 12,00 €',
    'btc': 'BTC 12,00 €',
    'usdt': 'USDT 12,00 €',
    'paytm': 'Paytm 12,00 €',
    'mpago': 'Mercado Pago 12,00 €',
  };

  for (final e in newRails.entries) {
    await tryCard(
      id: 'BS1.notes-${e.key}',
      lens: 'BS1',
      title: 'card reservation_payment_submitted notes=${e.value}',
      payload: {
        'kind': 'reservation_payment_submitted',
        'order_id': oid,
        'notes': e.value,
      },
    );
  }

  // controlo exacto BLBQ — não contar
  await tryCard(
    id: 'BS1.notes-clearpay-control',
    lens: 'BS1',
    countIfPersist: false,
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'Clearpay 12,00 €',
    },
  );
  await tryCard(
    id: 'BS1.notes-strike-control',
    lens: 'BS1',
    countIfPersist: false,
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'Strike 12,00 €',
    },
  );

  // zero-width no rail novo + no exacto
  const zw = '\u200B';
  const mongolian = '\u180E';
  const hangulFiller = '\u3164';
  const invSep = '\u2063';
  await tryCard(
    id: 'BS1.notes-zw-payoneer',
    lens: 'BS2',
    title: 'Payoneer com ZWSP (U+200B) nas notes',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'P${zw}ayoneer 12,00 €',
    },
  );
  await tryCard(
    id: 'BS1.notes-zw-clearpay',
    lens: 'BS2',
    title: 'Clearpay com U+180E / U+3164 / U+2063 (encoding novo)',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'C${mongolian}learpay 12,00 €',
    },
  );
  await tryCard(
    id: 'BS1.notes-hangul-clearpay',
    lens: 'BS2',
    title: 'Clearpay com Hangul filler U+3164',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'C${hangulFiller}learpay 12,00 €',
    },
  );
  await tryCard(
    id: 'BS1.notes-invsep-strike',
    lens: 'BS2',
    title: 'Strike com invisible separator U+2063',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'Stri${invSep}ke 12,00 €',
    },
  );

  // seguro_fleaber_paid com rail novo (precisa order paga)
  for (final e in newRails.entries) {
    await tryCard(
      id: 'BS1.seguro-${e.key}',
      lens: 'BS1',
      chat: paid.chatId,
      title: 'seguro_fleaber_paid label=${e.value}',
      payload: {
        'kind': 'seguro_fleaber_paid',
        'order_id': paid.oid,
        'total': paidTotal,
        'label': e.value,
      },
    );
  }
  await tryCard(
    id: 'BS1.seguro-payoneer-plain',
    lens: 'BS1',
    chat: paid.chatId,
    title: 'seguro_fleaber_paid label=Payoneer (sem montante)',
    payload: {
      'kind': 'seguro_fleaber_paid',
      'order_id': paid.oid,
      'total': paidTotal,
      'label': 'Payoneer',
    },
  );

  // meta extra controlo (exacto, não contar)
  await tryCard(
    id: 'BS1.meta-extra-control',
    lens: 'BS1',
    countIfPersist: false,
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'meta': {'rail': 'Payoneer'},
    },
  );

  // ---- BS2 encoding extra ----
  await tryCard(
    id: 'BS2.fullwidth-payoneer',
    lens: 'BS2',
    title: 'Payoneer fullwidth notes',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'Ｐａｙｏｎｅｅｒ 12,00 €',
    },
  );

  // overlong UTF-8 de "Clearpay 12,00 €" no campo notes (raw HTTP)
  // C = 0x43 → overlong 2-byte C1 83 (inválido; Postgres deve recusar)
  final overlongNotes = utf8.encode(
    '{"chat_id":"$chatId","sender_id":"${c.buyerId}","text":"FLEABER_JSON_V1:{\\"kind\\":\\"reservation_payment_submitted\\",\\"order_id\\":\\"$oid\\",\\"notes\\":\\"',
  );
  final overlongC = [0xC1, 0x83]; // overlong 'C'
  final restNotes = utf8.encode('learpay 12,00 €"}"}');
  final overlongBody = Uint8List.fromList([
    ...overlongNotes,
    ...overlongC,
    ...restNotes,
  ]);
  final overlongHit = await c.req(
    'POST',
    '/rest/v1/chat_messages',
    jwt: c.buyerJwt,
    rawBytes: overlongBody,
    contentType: 'application/json',
    extra: {'Prefer': 'return=representation'},
  );
  if (overlongHit.ok && overlongHit.firstId != null) {
    c.createdMsgIds.add(overlongHit.firstId!);
    c.hold(
      id: 'BS2.overlong-utf8-clearpay',
      lens: 'BS2',
      severity: 'P1',
      title: 'overlong UTF-8 atravessa denylist Clearpay nas notes',
      actor: 'buyer JWT',
      pre: 'body JSON com 0xC1 0x83 no lugar de C',
      repro: 'POST chat_messages raw overlong UTF-8 notes',
      expected: '400 invalid utf8 / notes_forbidden',
      obtained: overlongHit.brief,
    );
  } else {
    c.block('BS2.overlong-utf8-clearpay', 'BS2', 'overlong recusado',
        overlongHit.brief);
  }

  // ---- BS3 cronologia ----
  final past = DateTime.utc(2020, 1, 1);
  final insertPast = await c.postMsg(
    chatId: chatId,
    text: '$prefix past-insert',
    createdAt: past.toIso8601String(),
  );
  if (insertPast.ok && insertPast.firstId != null) {
    c.createdMsgIds.add(insertPast.firstId!);
    final row = await c.msgRow(insertPast.firstId!);
    final stored = DateTime.tryParse('${row?['created_at']}');
    final forcedNow = stored != null &&
        stored.isAfter(DateTime.now().toUtc().subtract(const Duration(minutes: 5)));
    if (!forcedNow) {
      c.hold(
        id: 'BS3.insert-created-at-past',
        lens: 'BS3',
        severity: 'P2',
        title: 'INSERT created_at no passado persistiu',
        actor: 'buyer JWT',
        pre: 'trigger deve forçar created_at := now()',
        repro: 'POST chat_messages created_at=2020-01-01',
        expected: 'created_at ≈ now()',
        obtained: row?['created_at'],
      );
    } else {
      c.block('BS3.insert-created-at-past', 'BS3', 'created_at forçado a now',
          row?['created_at']);
    }

    final patchAt = await c.rest(
      'PATCH',
      'chat_messages?id=eq.${insertPast.firstId}',
      jwt: c.buyerJwt,
      body: {'created_at': '2020-01-01T00:00:00Z'},
    );
    final after = await c.msgRow(insertPast.firstId!);
    final stored2 = DateTime.tryParse('${after?['created_at']}');
    final rewritten = stored2 != null && stored2.year == 2020;
    if (patchAt.ok && rewritten) {
      c.hold(
        id: 'BS3.patch-created-at',
        lens: 'BS3',
        severity: 'P1',
        title: 'PATCH created_at reescreve cronologia',
        actor: 'buyer JWT',
        pre: 'guard_update NEW.created_at := OLD.created_at',
        repro: 'PATCH chat_messages created_at=2020-01-01',
        expected: 'created_at imutável',
        obtained: after?['created_at'],
        evidence: {'http': patchAt.brief},
      );
    } else {
      c.block('BS3.patch-created-at', 'BS3', 'created_at imutável', {
        'http': patchAt.brief,
        'stored': after?['created_at'],
      });
    }
  } else {
    c.note('BS3.insert-past', 'insert past failed', insertPast.brief, lens: 'BS3');
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
        id: 'BS3.delete-json-card',
        lens: 'BS3',
        severity: 'P1',
        title: 'DELETE apaga card JSON de prova',
        actor: 'buyer JWT',
        pre: 'card reservation_payment_submitted',
        repro: 'DELETE chat_messages?id=eq.{id}',
        expected: 'chat_system_card_immutable',
        obtained: del.brief,
      );
    } else {
      c.block('BS3.delete-json-card', 'BS3', 'DELETE card recusado', del.brief);
    }
  }

  // ---- BS4 / BS6 URLs + storage ----
  final proofA =
      'order_proofs/${c.buyerId}/$oid/rtbs_a.png';
  final proofB =
      'order_proofs/${c.buyerId}/${paid2.oid}/rtbs_b.png';
  final upA = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$proofA',
    jwt: c.buyerJwt,
    rawBytes: png1x1,
    extra: {'x-upsert': 'true'},
  );
  final upB = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$proofB',
    jwt: c.buyerJwt,
    rawBytes: png1x1,
    extra: {'x-upsert': 'true'},
  );
  c.note('BS6.upload-a', 'upload prova A', upA.brief, lens: 'BS6');
  c.note('BS6.upload-b', 'upload prova B (outra encomenda própria)', upB.brief,
      lens: 'BS6');

  final signB = await c.req(
    'POST',
    '/storage/v1/object/sign/fleaber_private/$proofB',
    jwt: c.buyerJwt,
    body: {'expiresIn': 3600},
  );
  final signedB = signB.map?['signedURL']?.toString() ??
      signB.map?['signedUrl']?.toString() ??
      '';
  c.note('BS4.sign-b', 'signed URL encomenda B', signB.brief, lens: 'BS4');

  String absProof(String objectPath) =>
      '$stagingHost/storage/v1/object/fleaber_private/$objectPath';
  String authProof(String objectPath) =>
      '$stagingHost/storage/v1/object/authenticated/fleaber_private/$objectPath';

  // signed URL da própria outra encomenda no card da encomenda A
  if (signedB.isNotEmpty) {
    final absSigned = signedB.startsWith('http')
        ? signedB
        : '$stagingHost$signedB';
    await tryCard(
      id: 'BS4.signed-own-other-order',
      lens: 'BS4',
      title: 'proof_url = signed URL da outra encomenda do mesmo buyer',
      payload: {
        'kind': 'reservation_payment_submitted',
        'order_id': oid,
        'notes': 'ok',
        'proof_url': absSigned,
      },
    );
  }

  await tryCard(
    id: 'BS4.unsigned-own-other-order',
    lens: 'BS4',
    title: 'proof_url path da outra encomenda própria (sem sign)',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url': absProof(proofB),
    },
  );

  await tryCard(
    id: 'BS4.authenticated-own-other-order',
    lens: 'BS4',
    title: 'object/authenticated da outra encomenda própria',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url': authProof(proofB),
    },
  );

  await tryCard(
    id: 'BS4.authenticated-wrong-bucket',
    lens: 'BS4',
    title: 'object/authenticated bucket errado (avatars) com needle no path',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/authenticated/avatars/order_proofs/${c.buyerId}/$oid/x.png',
    },
  );

  await tryCard(
    id: 'BS4.authenticated-chat-media',
    lens: 'BS4',
    title: 'object/authenticated/chat_media com needle order_proofs',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/authenticated/chat_media/order_proofs/${c.buyerId}/$oid/x.png',
    },
  );

  // slash unicode U+FF0F
  const fwSlash = '／';
  await tryCard(
    id: 'BS4.unicode-slash-other-order',
    lens: 'BS4',
    title: 'proof_url com slash unicode ／ a apontar à outra encomenda',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oid${fwSlash}..${fwSlash}..${fwSlash}order_proofs/${c.buyerId}/${paid2.oid}/rtbs_b.png',
    },
  );

  // fullwidth dots U+FF0E (não ASCII ..)
  const fwDot = '．';
  await tryCard(
    id: 'BS4.fullwidth-dot-traversal',
    lens: 'BS4',
    title: 'proof_url travessia com pontos fullwidth ．．',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oid/$fwDot$fwDot/$fwDot$fwDot/order_proofs/${c.buyerId}/${paid2.oid}/rtbs_b.png',
    },
  );

  // exacto ../ — não contar
  await tryCard(
    id: 'BS4.dotdot-control',
    lens: 'BS4',
    countIfPersist: false,
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oid/../../../order_proofs/${c.buyerId}/${paid2.oid}/rtbs_b.png',
    },
  );

  await tryCard(
    id: 'BS4.honest-path',
    lens: 'BS4',
    countIfPersist: false,
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url': absProof(proofA),
    },
  );

  // chat_image wrong bucket
  await tryCard(
    id: 'BS4.chat-image-wrong-bucket',
    lens: 'BS4',
    title: 'chat_image object/authenticated bucket público',
    payload: {
      'kind': 'chat_image',
      'url':
          '$stagingHost/storage/v1/object/authenticated/public/rtbs.png',
    },
  );

  // ---- BS5 inbox rails novos ----
  for (final e in newRails.entries) {
    await tryInbox('BS5.inbox-${e.key}', e.value);
  }
  await tryInbox('BS5.inbox-clearpay-control', 'Clearpay 12,00 €', count: false);
  await tryInbox('BS5.inbox-zw-payoneer', 'P${zw}ayoneer 12,00 €');
  await tryInbox('BS5.inbox-hangul-clearpay', 'C${hangulFiller}learpay 12,00 €');
  await tryInbox('BS5.inbox-payoneer-plain', 'Payoneer');

  // ---- BS6 storage cross-user ----
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
      '${listRoot.body}${listB1.body}'.contains('rtbs_a');
  if (listRoot.ok && sawB1) {
    c.hold(
      id: 'BS6.list-cross-user',
      lens: 'BS6',
      severity: 'P1',
      title: 'B2 lista order_proofs de B1',
      actor: 'buyer2 JWT',
      pre: 'ficheiro B1 em order_proofs/{B1}/{order}/',
      repro: 'POST /storage/v1/object/list/fleaber_private prefix=order_proofs/',
      expected: 'lista vazia / 403',
      obtained: {'root': listRoot.brief, 'b1': listB1.brief},
    );
  } else {
    c.block('BS6.list-cross-user', 'BS6', 'list cross-user recusado', {
      'root': listRoot.brief,
      'b1': listB1.brief,
    });
  }

  final getB1 = await c.req(
    'GET',
    '/storage/v1/object/authenticated/fleaber_private/$proofA',
    jwt: c.buyer2Jwt,
  );
  if (getB1.ok && getB1.body.length >= 8) {
    c.hold(
      id: 'BS6.get-cross-user',
      lens: 'BS6',
      severity: 'P1',
      title: 'B2 lê prova de B1 via object/authenticated',
      actor: 'buyer2 JWT',
      pre: 'object order_proofs/B1/…',
      repro: 'GET authenticated fleaber_private/order_proofs/{B1}/…',
      expected: '403',
      obtained: getB1.brief,
    );
  } else {
    c.block('BS6.get-cross-user', 'BS6', 'GET cross-user recusado', getB1.brief);
  }

  final upB2 = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$proofA',
    jwt: c.buyer2Jwt,
    rawBytes: utf8.encode('stolen'),
    extra: {'x-upsert': 'true'},
  );
  if (upB2.ok) {
    c.hold(
      id: 'BS6.upload-cross-user',
      lens: 'BS6',
      severity: 'P1',
      title: 'B2 faz upload no prefixo order_proofs de B1',
      actor: 'buyer2 JWT',
      pre: 'policy insert_own',
      repro: 'POST storage object order_proofs/{B1}/{order}/rtbs_a.png',
      expected: '403',
      obtained: upB2.brief,
    );
  } else {
    c.block('BS6.upload-cross-user', 'BS6', 'upload B2 recusado', upB2.brief);
  }

  // GET signed B com anon
  if (signedB.isNotEmpty) {
    final absSigned = signedB.startsWith('http')
        ? signedB
        : '$stagingHost$signedB';
    final anonGet = await c.req('GET', absSigned);
    c.note('BS6.anon-signed-b', 'anon GET signed B', anonGet.brief, lens: 'BS6');
  }

  // ---- BS7 cross-user chat ----
  final b2OnB1 = await c.postMsg(
    chatId: chatId,
    text: 'B2 no chat B1',
    jwt: c.buyer2Jwt,
    sender: c.buyer2Id,
  );
  if (b2OnB1.ok) {
    c.hold(
      id: 'BS7.b2-insert-b1-chat',
      lens: 'BS7',
      severity: 'P1',
      title: 'B2 escreve no chat B1–seller',
      actor: 'buyer2 JWT',
      pre: 'B2 não é participante',
      repro: 'POST chat_messages chat_id=B1',
      expected: '403',
      obtained: b2OnB1.brief,
    );
  } else {
    c.block('BS7.b2-insert-b1-chat', 'BS7', 'B2 fora do chat', b2OnB1.brief);
  }

  final b2Read = await c.rest(
    'GET',
    'chat_messages?chat_id=eq.$chatId&select=id,text&limit=5',
    jwt: c.buyer2Jwt,
  );
  if (b2Read.ok && b2Read.list.isNotEmpty) {
    c.hold(
      id: 'BS7.b2-read-b1-chat',
      lens: 'BS7',
      severity: 'P1',
      title: 'B2 lê mensagens do chat B1–seller',
      actor: 'buyer2 JWT',
      pre: 'B2 não é participante',
      repro: 'GET chat_messages?chat_id=eq.B1',
      expected: '[] / 403',
      obtained: b2Read.brief,
    );
  } else {
    c.block('BS7.b2-read-b1-chat', 'BS7', 'B2 não lê chat B1', b2Read.brief);
  }

  final anonRead = await c.rest(
    'GET',
    'chat_messages?chat_id=eq.$chatId&select=id,text&limit=5',
  );
  if (anonRead.ok && anonRead.list.isNotEmpty) {
    c.hold(
      id: 'BS7.anon-read-chat',
      lens: 'BS7',
      severity: 'P1',
      title: 'anon lê chat_messages',
      actor: 'anon',
      pre: 'sem JWT',
      repro: 'GET chat_messages?chat_id=eq.B1',
      expected: '[] / 401',
      obtained: anonRead.brief,
    );
  } else {
    c.block('BS7.anon-read-chat', 'BS7', 'anon sem mensagens', anonRead.brief);
  }

  // seller forja seguro no chat do buyer
  await tryCard(
    id: 'BS7.seller-seguro-label',
    lens: 'BS7',
    jwt: c.sellerJwt,
    sender: c.sellerId,
    chat: paid.chatId,
    title: 'seller INSERT seguro_fleaber_paid label=Payoneer',
    payload: {
      'kind': 'seguro_fleaber_paid',
      'order_id': paid.oid,
      'total': paidTotal,
      'label': 'Payoneer',
    },
  );

  // ---- BS8 OCR Edge ----
  final liveHit = await c.rest('POST', 'lives', service: true, body: {
    'seller_id': c.sellerId,
    'title': '$prefix-ocr',
    'status': 'live',
    'is_active': true,
  });
  final liveId = liveHit.firstId;
  if (liveId != null) c.createdLiveIds.add(liveId);
  c.note('BS8.live', 'live fixture', liveHit.brief, lens: 'BS8');

  final fakeTok = await c.edge(
    'ingest-ocr-reservation',
    {
      'live_id': liveId ?? '00000000-0000-0000-0000-000000000000',
      'ocr_line_hash': 'rtbshash12345678',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'ocr_raw_line': 'Payoneer paid 12 EUR ref A1',
      'ref_number': 1,
    },
    jwt: c.buyerJwt,
    extra: {'x-device-token': 'rtbs-fake-token-payoneer'},
  );
  if (fakeTok.ok) {
    c.hold(
      id: 'BS8.ocr-fake-token',
      lens: 'BS8',
      severity: 'P1',
      title: 'OCR Edge aceita device token falso (rail Payoneer na linha)',
      actor: 'buyer JWT + x-device-token falso',
      pre: 'sem pairing',
      repro: 'POST ingest-ocr-reservation x-device-token=rtbs-fake',
      expected: '401 invalid_token',
      obtained: fakeTok.brief,
    );
  } else {
    c.block('BS8.ocr-fake-token', 'BS8', 'token falso recusado', fakeTok.brief);
  }

  final rpcOcr = await c.rpc(
    'batata_ingest_ocr_reservation_v2',
    {
      'p_device_token': 'rtbs-fake',
      'p_live_id': liveId,
      'p_external_display_name': 'Payoneer',
      'p_external_buyer_ref': 'x',
      'p_ocr_raw_line': 'Payoneer 12,00 €',
      'p_ocr_line_hash': 'rtbshash12345678',
      'p_detected_at': DateTime.now().toUtc().toIso8601String(),
      'p_requested_qty': 1,
    },
    jwt: c.buyerJwt,
  );
  if (rpcOcr.ok && (rpcOcr.map?['ok'] == true)) {
    c.hold(
      id: 'BS8.ocr-rpc-jwt',
      lens: 'BS8',
      severity: 'P1',
      title: 'JWT chama ingest OCR v2 com token falso',
      actor: 'buyer JWT',
      pre: 'RPC SECURITY DEFINER',
      repro: 'POST rpc/batata_ingest_ocr_reservation_v2',
      expected: '403 / invalid_token',
      obtained: rpcOcr.brief,
    );
  } else {
    c.block('BS8.ocr-rpc-jwt', 'BS8', 'RPC OCR JWT recusado', rpcOcr.brief);
  }

  final ocrAnon = await c.edge(
    'ingest-ocr-reservation',
    {
      'live_id': liveId,
      'ocr_line_hash': 'rtbshashanon0001',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'ocr_raw_line': 'USDT paid 12 EUR',
      'ref_number': 1,
    },
  );
  if (ocrAnon.ok) {
    c.hold(
      id: 'BS8.ocr-anon',
      lens: 'BS8',
      severity: 'P1',
      title: 'OCR Edge aceita anon sem token',
      actor: 'anon',
      pre: 'sem JWT / sem device token',
      repro: 'POST ingest-ocr-reservation anon',
      expected: '401',
      obtained: ocrAnon.brief,
    );
  } else {
    c.block('BS8.ocr-anon', 'BS8', 'anon OCR recusado', ocrAnon.brief);
  }

  await c.endLives();

  final out = {
    'auditor': 'REDTEAM_BLIND_BS_CHAT_POS_BLBQ_v1',
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
      'paid2_order': paid2.oid,
      'paid2_chat': paid2.chatId,
      'live': liveId,
      'buyer2': c.buyer2Id,
    },
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
  };
  await dumpJson('${outDir()}/pass1.json', out);
  stdout.writeln(
      'FINDINGS=${c.findings.length} BLOCKED=${c.blocked.length} LENSES=${c.lensesHit}');
}
