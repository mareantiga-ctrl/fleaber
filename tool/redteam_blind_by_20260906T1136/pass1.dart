/// REDTEAM_BLIND_BY_CHAT_POS_BRBW_v1 — pass1. Staging only. No fixes.
import 'dart:convert';
import 'dart:io';

import '_rtby.dart';

Future<void> main() async {
  final c = Rtby.fromEnv(loadEnv());
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
          pre: 'denylist BRBW sem este rail/encoding/URL',
          repro: 'POST chat_messages FLEABER_JSON_V1:${jsonEncode(payload)}',
          expected:
              'chat_system_card_notes_forbidden / url_denied / label_mismatch',
          obtained: h.brief,
          evidence: {
            'id': h.firstId,
            'kind': payload['kind'],
            'payload': payload,
          },
        );
      } else {
        c.note(id, 'persistiu (exacto/controlo, não contar)', h.brief,
            lens: lens);
      }
    } else {
      c.block(id, lens, 'recusado', h.brief);
    }
    return persisted ? h.map : null;
  }

  Future<void> tryInbox(String id, String text,
      {bool count = true, String severity = 'P1'}) async {
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
          lens: 'BY5',
          severity: severity,
          title: 'inbox last_message forjado: $text',
          actor: 'buyer JWT',
          pre: 'chats_update_participants',
          repro: 'PATCH chats.last_message=$text',
          expected: 'chat_inbox_preview_forbidden',
          obtained: stored,
        );
      } else {
        c.note(id, 'inbox persistiu (exacto, não contar)', stored, lens: 'BY5');
      }
    } else {
      c.block(id, 'BY5', 'inbox recusado', {'http': h.brief, 'stored': stored});
    }
  }

  // ---- BY1 cards · rails novos (não Payoneer/WU) ----
  const newRails = <String, String>{
    'skrill': 'Skrill 12,00 €',
    'neteller': 'Neteller 12,00 €',
    'revbiz': 'Revolut Business 12,00 €',
    'enviado-mb': 'enviado MB',
    'enviado-mb-amt': 'enviado MB 12,00 €',
    'paysafe': 'Paysafecard 12,00 €',
    'moneygram': 'MoneyGram 12,00 €',
    'gcash': 'GCash 12,00 €',
  };

  for (final e in newRails.entries) {
    await tryCard(
      id: 'BY1.notes-${e.key}',
      lens: 'BY1',
      title: 'card reservation_payment_submitted notes=${e.value}',
      payload: {
        'kind': 'reservation_payment_submitted',
        'order_id': oid,
        'notes': e.value,
      },
    );
  }

  // exactos BS/BRBW — não contar
  await tryCard(
    id: 'BY1.notes-payoneer-control',
    lens: 'BY1',
    countIfPersist: false,
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'Payoneer 12,00 €',
    },
  );
  await tryCard(
    id: 'BY1.notes-wu-control',
    lens: 'BY1',
    countIfPersist: false,
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'Western Union 12,00 €',
    },
  );

  // seguro_fleaber_paid com rail novo
  for (final e in newRails.entries) {
    await tryCard(
      id: 'BY1.seguro-${e.key}',
      lens: 'BY1',
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
    id: 'BY1.seguro-payoneer-control',
    lens: 'BY1',
    chat: paid.chatId,
    countIfPersist: false,
    payload: {
      'kind': 'seguro_fleaber_paid',
      'order_id': paid.oid,
      'total': paidTotal,
      'label': 'Payoneer 12,00 €',
    },
  );

  // ---- BY2 encoding · bidi / soft hyphen / fillers novos ----
  const rlo = '\u202E'; // bidi override (BRBW strip chr 8238)
  const shy = '\u00AD'; // soft hyphen (BRBW strip chr 173)
  const isss = '\u206A'; // inhibit symmetric swapping — fora do strip
  const cgj = '\u034F'; // combining grapheme joiner — fora
  const hwhf = '\uFFA0'; // halfwidth hangul filler — fora
  const alm = '\u061C'; // arabic letter mark — fora
  const fvs1 = '\u180B'; // mongolian FVS1 — fora (U+180E foi fechado)
  const mongolian = '\u180E'; // exacto BS — não contar

  Future<void> encNotes(String id, String notes, {bool count = true}) {
    return tryCard(
      id: id,
      lens: 'BY2',
      countIfPersist: count,
      title: 'notes encoding $id',
      payload: {
        'kind': 'reservation_payment_submitted',
        'order_id': oid,
        'notes': notes,
      },
    );
  }

  // prompt: bidi override + soft hyphen mid-rail sobre rail FECHADO
  await encNotes('BY2.bidi-clearpay', 'Clea${rlo}rpay 12,00 €');
  await encNotes('BY2.shy-clearpay', 'Clea${shy}rpay 12,00 €');
  await encNotes('BY2.shy-payoneer', 'Payo${shy}neer 12,00 €');
  await encNotes('BY2.bidi-payoneer', 'Payo${rlo}neer 12,00 €');

  // exacto U+180E Clearpay — não contar
  await encNotes('BY2.u180e-clearpay-control', 'C${mongolian}learpay 12,00 €',
      count: false);

  // encoding NOVO (não no strip BRBW) sobre rail fechado
  await encNotes('BY2.isss-clearpay', 'Clea${isss}rpay 12,00 €');
  await encNotes('BY2.cgj-clearpay', 'Clea${cgj}rpay 12,00 €');
  await encNotes('BY2.hwhf-clearpay', 'Clea${hwhf}rpay 12,00 €');
  await encNotes('BY2.alm-clearpay', 'Clea${alm}rpay 12,00 €');
  await encNotes('BY2.fvs1-clearpay', 'Clea${fvs1}rpay 12,00 €');
  await encNotes('BY2.isss-payoneer', 'Payo${isss}neer 12,00 €');

  // soft hyphen no rail NOVO (Skrill) — se persistir, é a classe BY1 não BY2
  await encNotes('BY2.shy-skrill', 'Skri${shy}ll 12,00 €');

  // inbox encoding
  await tryInbox('BY5.inbox-bidi-clearpay', 'Clea${rlo}rpay 12,00 €');
  await tryInbox('BY5.inbox-shy-clearpay', 'Clea${shy}rpay 12,00 €');
  await tryInbox('BY5.inbox-isss-clearpay', 'Clea${isss}rpay 12,00 €');
  await tryInbox('BY5.inbox-cgj-clearpay', 'Clea${cgj}rpay 12,00 €');
  await tryInbox('BY2.inbox-u180e-control', 'C${mongolian}learpay 12,00 €',
      count: false);

  // ---- BY3 cronologia ----
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
        stored.isAfter(
            DateTime.now().toUtc().subtract(const Duration(minutes: 5)));
    if (!forcedNow) {
      c.hold(
        id: 'BY3.insert-created-at-past',
        lens: 'BY3',
        severity: 'P2',
        title: 'INSERT created_at no passado persistiu',
        actor: 'buyer JWT',
        pre: 'trigger deve forçar created_at := now()',
        repro: 'POST chat_messages created_at=2020-01-01',
        expected: 'created_at ≈ now()',
        obtained: row?['created_at'],
      );
    } else {
      c.block('BY3.insert-created-at-past', 'BY3', 'created_at forçado a now',
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
        id: 'BY3.patch-created-at',
        lens: 'BY3',
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
      c.block('BY3.patch-created-at', 'BY3', 'created_at imutável', {
        'http': patchAt.brief,
        'stored': after?['created_at'],
      });
    }
  } else {
    c.note('BY3.insert-past', 'insert past failed', insertPast.brief,
        lens: 'BY3');
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
        id: 'BY3.delete-json-card',
        lens: 'BY3',
        severity: 'P1',
        title: 'DELETE apaga card JSON de prova',
        actor: 'buyer JWT',
        pre: 'card reservation_payment_submitted',
        repro: 'DELETE chat_messages?id=eq.{id}',
        expected: 'chat_system_card_immutable',
        obtained: del.brief,
      );
    } else {
      c.block('BY3.delete-json-card', 'BY3', 'DELETE card recusado', del.brief);
    }
  }

  // ---- BY4 / BY6 URLs + storage ----
  final proofA = 'order_proofs/${c.buyerId}/$oid/rtby_a.png';
  final proofB = 'order_proofs/${c.buyerId}/${paid2.oid}/rtby_b.png';
  final upA = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$proofA',
    jwt: c.buyerJwt,
    rawBytes: png1x1,
    contentType: 'image/png',
    extra: {'x-upsert': 'true'},
  );
  final upB = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$proofB',
    jwt: c.buyerJwt,
    rawBytes: png1x1,
    contentType: 'image/png',
    extra: {'x-upsert': 'true'},
  );
  c.note('BY6.upload-a', 'upload prova A', upA.brief, lens: 'BY6');
  c.note('BY6.upload-b', 'upload prova B (outra encomenda própria)', upB.brief,
      lens: 'BY6');

  final signB = await c.req(
    'POST',
    '/storage/v1/object/sign/fleaber_private/$proofB',
    jwt: c.buyerJwt,
    body: {'expiresIn': 3600},
  );
  final signedB = signB.map?['signedURL']?.toString() ??
      signB.map?['signedUrl']?.toString() ??
      '';
  c.note('BY4.sign-b', 'signed URL encomenda B', signB.brief, lens: 'BY4');

  String absProof(String objectPath) =>
      '$stagingHost/storage/v1/object/fleaber_private/$objectPath';
  String authProof(String objectPath) =>
      '$stagingHost/storage/v1/object/authenticated/fleaber_private/$objectPath';

  String absSignedUrl(String signed) {
    if (signed.startsWith('http')) return signed;
    if (signed.startsWith('/object/')) {
      return '$stagingHost/storage/v1$signed';
    }
    if (signed.startsWith('/storage/')) return '$stagingHost$signed';
    return '$stagingHost$signed';
  }

  // signed URL da própria outra encomenda no card da encomenda A (prompt)
  if (signedB.isNotEmpty) {
    final absSigned = absSignedUrl(signedB);
    await tryCard(
      id: 'BY4.signed-own-other-order',
      lens: 'BY4',
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
    id: 'BY4.unsigned-own-other-order',
    lens: 'BY4',
    title: 'proof_url path da outra encomenda própria (sem sign)',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url': absProof(proofB),
    },
  );

  // %c1%9c overlong backslash (prompt) — canónico BRBW só trata %c0%ae / %c0%af
  await tryCard(
    id: 'BY4.c1-9c-backslash',
    lens: 'BY4',
    severity: 'P2',
    title: 'proof_url travessia %c1%9c (overlong backslash)',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oid/%c1%9c../%c1%9c../order_proofs/${c.buyerId}/${paid2.oid}/rtby_b.png',
    },
  );

  // double-encoding %252e%252e (prompt)
  await tryCard(
    id: 'BY4.double-encoding-dot',
    lens: 'BY4',
    severity: 'P2',
    title: 'proof_url double-encoding %252e%252e',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oid/%252e%252e/%252e%252e/order_proofs/${c.buyerId}/${paid2.oid}/rtby_b.png',
    },
  );

  // 3-byte overlong dot %e0%80%ae
  await tryCard(
    id: 'BY4.e0-80-ae-overlong-dot',
    lens: 'BY4',
    severity: 'P2',
    title: 'proof_url %e0%80%ae (overlong 3-byte dot)',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oid/%e0%80%ae%e0%80%ae/%e0%80%ae%e0%80%ae/order_proofs/${c.buyerId}/${paid2.oid}/rtby_b.png',
    },
  );

  // exacto ．． / %c0%ae — não contar
  const fwDot = '．';
  await tryCard(
    id: 'BY4.fullwidth-dot-control',
    lens: 'BY4',
    countIfPersist: false,
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oid/$fwDot$fwDot/$fwDot$fwDot/order_proofs/${c.buyerId}/${paid2.oid}/rtby_b.png',
    },
  );
  await tryCard(
    id: 'BY4.c0ae-control',
    lens: 'BY4',
    countIfPersist: false,
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oid/%c0%ae%c0%ae/%c0%ae%c0%ae/order_proofs/${c.buyerId}/${paid2.oid}/rtby_b.png',
    },
  );

  await tryCard(
    id: 'BY4.honest-path',
    lens: 'BY4',
    countIfPersist: false,
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url': absProof(proofA),
    },
  );

  await tryCard(
    id: 'BY4.authenticated-own-other-order',
    lens: 'BY4',
    title: 'object/authenticated da outra encomenda própria',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url': authProof(proofB),
    },
  );

  // ---- BY5 inbox rails novos ----
  for (final e in newRails.entries) {
    await tryInbox('BY5.inbox-${e.key}', e.value);
  }
  await tryInbox('BY5.inbox-payoneer-control', 'Payoneer 12,00 €', count: false);
  await tryInbox('BY5.inbox-wu-control', 'Western Union 12,00 €', count: false);

  // ---- BY6 storage cross-user ----
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
      '${listRoot.body}${listB1.body}'.contains('rtby_a');
  if (listRoot.ok && sawB1) {
    c.hold(
      id: 'BY6.list-cross-user',
      lens: 'BY6',
      severity: 'P1',
      title: 'B2 lista order_proofs de B1',
      actor: 'buyer2 JWT',
      pre: 'ficheiro B1 em order_proofs/{B1}/{order}/',
      repro: 'POST /storage/v1/object/list/fleaber_private prefix=order_proofs/',
      expected: 'lista vazia / 403',
      obtained: {'root': listRoot.brief, 'b1': listB1.brief},
    );
  } else {
    c.block('BY6.list-cross-user', 'BY6', 'list cross-user recusado', {
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
      id: 'BY6.get-cross-user',
      lens: 'BY6',
      severity: 'P1',
      title: 'B2 lê prova de B1 via object/authenticated',
      actor: 'buyer2 JWT',
      pre: 'object order_proofs/B1/…',
      repro: 'GET authenticated fleaber_private/order_proofs/{B1}/…',
      expected: '403',
      obtained: getB1.brief,
    );
  } else {
    c.block('BY6.get-cross-user', 'BY6', 'GET cross-user recusado', getB1.brief);
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
      id: 'BY6.upload-cross-user',
      lens: 'BY6',
      severity: 'P1',
      title: 'B2 faz upload no prefixo order_proofs de B1',
      actor: 'buyer2 JWT',
      pre: 'policy insert_own',
      repro: 'POST storage object order_proofs/{B1}/{order}/rtby_a.png',
      expected: '403',
      obtained: upB2.brief,
    );
  } else {
    c.block('BY6.upload-cross-user', 'BY6', 'upload B2 recusado', upB2.brief);
  }

  if (signedB.isNotEmpty) {
    final absSigned = absSignedUrl(signedB);
    final anonGet = await c.req('GET', absSigned);
    c.note('BY6.anon-signed-b', 'anon GET signed B',
        '${anonGet.status} len=${anonGet.body.length}',
        lens: 'BY6');
  }

  // GET loot para URLs hostis se o card persistiu
  Future<void> lootGet(String id, String path) async {
    final h = await c.req('GET', path, jwt: c.buyerJwt);
    final loot = h.ok &&
        h.body.length >= 8 &&
        (h.body.startsWith('\u0089PNG') ||
            h.body.contains('PNG') ||
            h.status == 200 && h.body.length > 20);
    c.note(id, 'GET loot', '${h.status} len=${h.body.length} ${h.snippet}',
        lens: 'BY4');
    if (loot && path.contains(paid2.oid)) {
      c.hold(
        id: '$id-loot',
        lens: 'BY4',
        severity: 'P1',
        title: 'GET resolveu prova da outra encomenda via path hostil',
        actor: 'buyer JWT',
        pre: 'PNG em order_proofs/{B1}/{oidB}',
        repro: 'GET $path',
        expected: '400/404 sem bytes PNG',
        obtained: '${h.status} len=${h.body.length}',
      );
    }
  }

  await lootGet(
    'BY4.loot-c19c-auth',
    '/storage/v1/object/authenticated/fleaber_private/order_proofs/${c.buyerId}/$oid/%c1%9c../%c1%9c../order_proofs/${c.buyerId}/${paid2.oid}/rtby_b.png',
  );
  await lootGet(
    'BY4.loot-double-auth',
    '/storage/v1/object/authenticated/fleaber_private/order_proofs/${c.buyerId}/$oid/%252e%252e/%252e%252e/order_proofs/${c.buyerId}/${paid2.oid}/rtby_b.png',
  );
  await lootGet(
    'BY4.loot-e080ae-auth',
    '/storage/v1/object/authenticated/fleaber_private/order_proofs/${c.buyerId}/$oid/%e0%80%ae%e0%80%ae/%e0%80%ae%e0%80%ae/order_proofs/${c.buyerId}/${paid2.oid}/rtby_b.png',
  );
  final honestB = await c.req(
    'GET',
    '/storage/v1/object/authenticated/fleaber_private/$proofB',
    jwt: c.buyerJwt,
  );
  c.note('BY6.get-honest-b', 'GET prova B (mesmo buyer)',
      '${honestB.status} len=${honestB.body.length}',
      lens: 'BY6');

  // ---- BY7 cross-user chat ----
  final b2OnB1 = await c.postMsg(
    chatId: chatId,
    text: 'B2 no chat B1',
    jwt: c.buyer2Jwt,
    sender: c.buyer2Id,
  );
  if (b2OnB1.ok) {
    c.hold(
      id: 'BY7.b2-insert-b1-chat',
      lens: 'BY7',
      severity: 'P1',
      title: 'B2 escreve no chat B1–seller',
      actor: 'buyer2 JWT',
      pre: 'B2 não é participante',
      repro: 'POST chat_messages chat_id=B1',
      expected: '403',
      obtained: b2OnB1.brief,
    );
  } else {
    c.block('BY7.b2-insert-b1-chat', 'BY7', 'B2 fora do chat', b2OnB1.brief);
  }

  final b2Read = await c.rest(
    'GET',
    'chat_messages?chat_id=eq.$chatId&select=id,text&limit=5',
    jwt: c.buyer2Jwt,
  );
  if (b2Read.ok && b2Read.list.isNotEmpty) {
    c.hold(
      id: 'BY7.b2-read-b1-chat',
      lens: 'BY7',
      severity: 'P1',
      title: 'B2 lê mensagens do chat B1–seller',
      actor: 'buyer2 JWT',
      pre: 'B2 não é participante',
      repro: 'GET chat_messages?chat_id=eq.B1',
      expected: '[] / 403',
      obtained: b2Read.brief,
    );
  } else {
    c.block('BY7.b2-read-b1-chat', 'BY7', 'B2 não lê chat B1', b2Read.brief);
  }

  final anonRead = await c.rest(
    'GET',
    'chat_messages?chat_id=eq.$chatId&select=id,text&limit=5',
  );
  if (anonRead.ok && anonRead.list.isNotEmpty) {
    c.hold(
      id: 'BY7.anon-read-chat',
      lens: 'BY7',
      severity: 'P1',
      title: 'anon lê chat_messages',
      actor: 'anon',
      pre: 'sem JWT',
      repro: 'GET chat_messages?chat_id=eq.B1',
      expected: '[] / 401',
      obtained: anonRead.brief,
    );
  } else {
    c.block('BY7.anon-read-chat', 'BY7', 'anon sem mensagens', anonRead.brief);
  }

  await tryCard(
    id: 'BY7.seller-seguro-label',
    lens: 'BY7',
    jwt: c.sellerJwt,
    sender: c.sellerId,
    chat: paid.chatId,
    title: 'seller INSERT seguro_fleaber_paid label=Skrill',
    payload: {
      'kind': 'seguro_fleaber_paid',
      'order_id': paid.oid,
      'total': paidTotal,
      'label': 'Skrill',
    },
  );

  // ---- BY8 OCR Edge ----
  final liveHit = await c.rest('POST', 'lives', service: true, body: {
    'seller_id': c.sellerId,
    'title': '$prefix-ocr',
    'status': 'live',
    'is_active': true,
  });
  final liveId = liveHit.firstId;
  if (liveId != null) c.createdLiveIds.add(liveId);
  c.note('BY8.live', 'live fixture', liveHit.brief, lens: 'BY8');

  final fakeTok = await c.edge(
    'ingest-ocr-reservation',
    {
      'live_id': liveId ?? '00000000-0000-0000-0000-000000000000',
      'ocr_line_hash': 'rtbyhash12345678',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'ocr_raw_line': 'Skrill paid 12 EUR ref A1',
      'ref_number': 1,
    },
    jwt: c.buyerJwt,
    extra: {'x-device-token': 'rtby-fake-token-skrill'},
  );
  if (fakeTok.ok) {
    c.hold(
      id: 'BY8.ocr-fake-token',
      lens: 'BY8',
      severity: 'P1',
      title: 'OCR Edge aceita device token falso (rail Skrill na linha)',
      actor: 'buyer JWT + x-device-token falso',
      pre: 'sem pairing',
      repro: 'POST ingest-ocr-reservation x-device-token=rtby-fake',
      expected: '401 invalid_token',
      obtained: fakeTok.brief,
    );
  } else {
    c.block('BY8.ocr-fake-token', 'BY8', 'token falso recusado', fakeTok.brief);
  }

  final rpcOcr = await c.rpc(
    'batata_ingest_ocr_reservation_v2',
    {
      'p_device_token': 'rtby-fake',
      'p_live_id': liveId,
      'p_external_display_name': 'Skrill',
      'p_external_buyer_ref': 'x',
      'p_ocr_raw_line': 'Skrill 12,00 €',
      'p_ocr_line_hash': 'rtbyhash12345678',
      'p_detected_at': DateTime.now().toUtc().toIso8601String(),
      'p_requested_qty': 1,
    },
    jwt: c.buyerJwt,
  );
  if (rpcOcr.ok && (rpcOcr.map?['ok'] == true)) {
    c.hold(
      id: 'BY8.ocr-rpc-jwt',
      lens: 'BY8',
      severity: 'P1',
      title: 'JWT chama ingest OCR v2 com token falso',
      actor: 'buyer JWT',
      pre: 'RPC SECURITY DEFINER',
      repro: 'POST rpc/batata_ingest_ocr_reservation_v2',
      expected: '403 / invalid_token',
      obtained: rpcOcr.brief,
    );
  } else {
    c.block('BY8.ocr-rpc-jwt', 'BY8', 'RPC OCR JWT recusado', rpcOcr.brief);
  }

  final ocrAnon = await c.edge(
    'ingest-ocr-reservation',
    {
      'live_id': liveId,
      'ocr_line_hash': 'rtbyhashanon0001',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'ocr_raw_line': 'Neteller paid 12 EUR',
      'ref_number': 1,
    },
  );
  if (ocrAnon.ok) {
    c.hold(
      id: 'BY8.ocr-anon',
      lens: 'BY8',
      severity: 'P1',
      title: 'OCR Edge aceita anon sem token',
      actor: 'anon',
      pre: 'sem JWT / sem device token',
      repro: 'POST ingest-ocr-reservation anon',
      expected: '401',
      obtained: ocrAnon.brief,
    );
  } else {
    c.block('BY8.ocr-anon', 'BY8', 'anon OCR recusado', ocrAnon.brief);
  }

  await c.endLives();

  final out = {
    'auditor': 'REDTEAM_BLIND_BY_CHAT_POS_BRBW_v1',
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
      'proof_a': proofA,
      'proof_b': proofB,
    },
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
  };
  await dumpJson('${outDir()}/pass1.json', out);
  stdout.writeln(
      'FINDINGS=${c.findings.length} BLOCKED=${c.blocked.length} LENSES=${c.lensesHit}');
}
