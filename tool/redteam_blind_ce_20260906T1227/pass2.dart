/// REDTEAM_BLIND_CE_CHAT_POS_BXCC_v1 — pass2 CE-B/C/D/E.
/// Encoding/URL/path · storage/OCR · cronologia/inbox/cross-user · composição.
/// Staging only. No fixes.
import 'dart:convert';
import 'dart:io';

import '_rtce.dart';

Future<void> main() async {
  final c = Rtce.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  final sku = await c.createProduct(title: '$prefix-ceb', price: 12);
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
  final paidA = await c.payToPago();
  final paidB = await c.payToPago();
  if (chatId == null || oid == null || paidA == null || paidB == null) {
    stderr.writeln('fixture fail');
    exit(4);
  }
  final b = c.buyerId!;
  final oidA = paidA.oid;
  final oidB = paidB.oid;
  final walBefore = await c.walletBal(c.sellerId);

  Future<void> tryCard({
    required String id,
    required String lens,
    required Map<String, Object?> payload,
    String? title,
    String severity = 'P1',
    String? jwt,
    String? chat,
    String? sender,
    bool countIfPersist = true,
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
          pre: 'canonical BXCC + prefix order_proofs',
          repro: 'POST chat_messages ${jsonEncode(payload)}',
          expected: 'chat_system_card_url_denied / notes_forbidden',
          obtained: h.brief,
          evidence: {'id': h.firstId, 'payload': payload},
        );
      } else {
        c.note(id, 'persistiu (controlo)', h.brief, lens: lens);
      }
    } else {
      c.block(id, lens, 'recusado', h.brief);
    }
  }

  String absProof(String objectPath) =>
      '$stagingHost/storage/v1/object/fleaber_private/$objectPath';

  String proof(String uid, String orderId, String file) =>
      'order_proofs/$uid/$orderId/$file';

  // upload prova legítima A
  final objA = proof(b, oidA, 'rtce_a.png');
  final upA = await c.storageUpload(
    objectName: objA,
    bytes: png1x1,
    jwt: c.buyerJwt,
  );
  c.note('CEC.upload-a', 'upload prova própria A', upA.brief, lens: 'CE6');

  // ---- CE-B encoding / URL / path (NÃO %252e exacto BXCC) ----
  final paths = <String, String>{
    'overlong2':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/%c0%ae%c0%ae/%c0%ae%c0%ae/order_proofs/$b/$oidB/rtce_b.png',
    'dotdot-slash':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/%2e%2e%2f%2e%2e%2forder_proofs/$b/$oidB/rtce_b.png',
    'triple-encode':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/%25252e%25252e/%25252e%25252e/order_proofs/$b/$oidB/rtce_b.png',
    'fullwidth-dots':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/\uFF0E\uFF0E/\uFF0E\uFF0E/order_proofs/$b/$oidB/rtce_b.png',
    'two-dot-leader':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/\u2025/\u2025/order_proofs/$b/$oidB/rtce_b.png',
    'overlong4':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/%f0%80%80%ae%f0%80%80%ae/order_proofs/$b/$oidB/rtce_b.png',
    'iis-u':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/%u002e%u002e/%u002e%u002e/order_proofs/$b/$oidB/rtce_b.png',
    'rlo-path':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/\u202E..\$/x.png',
    'file-scheme':
        'file:///storage/v1/object/fleaber_private/order_proofs/$b/$oidA/rtce_a.png',
    'javascript': 'javascript:alert(1)',
    'data-url': 'data:image/png;base64,AAAA',
    'evil-host':
        'https://evil.example/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/rtce_a.png',
    'other-order': absProof(proof(b, oidB, 'rtce_b.png')),
  };

  for (final e in paths.entries) {
    await tryCard(
      id: 'CEB.proof-${e.key}',
      lens: 'CE4',
      title: 'proof_url ${e.key}',
      payload: {
        'kind': 'reservation_payment_submitted',
        'order_id': oidA,
        'notes': 'comprovativo envio',
        'proof_url': e.value,
      },
    );
  }

  // chat_image schemes
  await tryCard(
    id: 'CEB.img-file',
    lens: 'CE4',
    title: 'chat_image file://',
    payload: {
      'kind': 'chat_image',
      'url': 'file:///storage/v1/object/sign/fleaber_private/x.png',
    },
  );
  await tryCard(
    id: 'CEB.img-js',
    lens: 'CE4',
    title: 'chat_image javascript:',
    payload: {
      'kind': 'chat_image',
      'url': 'javascript:alert(1)',
    },
  );

  // disputa path alheio — precisa disputa? tentar proof_url apontando order_disputes de outro
  await tryCard(
    id: 'CEB.proof-disputes-other',
    lens: 'CE4',
    title: 'proof_url aponta order_disputes de outro order',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oidA,
      'notes': 'foto',
      'proof_url':
          '$stagingHost/storage/v1/object/authenticated/fleaber_private/order_disputes/$b/$oidB/x.png',
    },
  );

  // ---- CE-C storage ----
  final objB2guess = 'order_proofs/${c.buyer2Id}/$oidB/rtce_steal.png';
  final listAlien = await c.storageList(
    prefix: 'order_proofs/${c.buyer2Id}/',
    jwt: c.buyerJwt,
  );
  c.note('CEC.list-b2', 'B1 lista prefixo B2', listAlien.brief, lens: 'CE6');
  final listed = listAlien.list;
  if (listAlien.ok && listed.isNotEmpty) {
    c.hold(
      id: 'CEC.list-alien',
      lens: 'CE6',
      severity: 'P1',
      title: 'B1 listou objectos no prefixo de B2',
      actor: 'buyer JWT',
      pre: 'storage RLS fleaber_private',
      repro: 'POST /storage/v1/object/list/fleaber_private prefix=order_proofs/{b2}',
      expected: 'lista vazia / 4xx',
      obtained: listAlien.brief,
    );
  } else {
    c.block('CEC.list-alien', 'CE6', 'list B2 recusado/vazio', listAlien.brief);
  }

  final upAlien = await c.storageUpload(
    objectName: 'order_proofs/${c.buyer2Id}/00000000-0000-0000-0000-000000000099/x.png',
    bytes: png1x1,
    jwt: c.buyerJwt,
  );
  if (upAlien.ok) {
    c.hold(
      id: 'CEC.upload-alien',
      lens: 'CE6',
      severity: 'P0',
      title: 'B1 fez upload no path de B2',
      actor: 'buyer JWT',
      pre: 'storage insert RLS',
      repro: 'POST object/fleaber_private/order_proofs/{b2}/…',
      expected: '403/RLS',
      obtained: upAlien.brief,
    );
  } else {
    c.block('CEC.upload-alien', 'CE6', 'upload path B2 recusado', upAlien.brief);
  }

  final getAasB2 = await c.storageGet(objA, jwt: c.buyer2Jwt);
  if (getAasB2.ok) {
    c.hold(
      id: 'CEC.get-cross',
      lens: 'CE6',
      severity: 'P1',
      title: 'B2 leu prova de B1',
      actor: 'buyer2 JWT',
      pre: 'storage select RLS',
      repro: 'GET object/authenticated/fleaber_private/$objA',
      expected: '403',
      obtained: getAasB2.brief,
    );
  } else {
    c.block('CEC.get-cross', 'CE6', 'GET prova alheia recusado', getAasB2.brief);
  }

  final overwrite = await c.storageUpload(
    objectName: objA,
    bytes: png1x1,
    jwt: c.buyer2Jwt,
  );
  if (overwrite.ok) {
    c.hold(
      id: 'CEC.overwrite',
      lens: 'CE6',
      severity: 'P0',
      title: 'B2 overwrite prova de B1',
      actor: 'buyer2 JWT',
      pre: 'storage update RLS',
      repro: 'POST x-upsert object $objA',
      expected: '403',
      obtained: overwrite.brief,
    );
  } else {
    c.block('CEC.overwrite', 'CE6', 'overwrite alheio recusado', overwrite.brief);
  }

  // OCR Edge — token após kick / token outro / replay
  final ocrBody = {
    'live_id': '00000000-0000-0000-0000-000000000001',
    'ocr_line_hash': 'rtce1227deadbeef',
    'detected_at': DateTime.now().toUtc().toIso8601String(),
    'ocr_raw_line': 'WeChat Pay confirmado 12,00 €',
    'ref_number': 1,
    'external_display_name': 'RTCE',
  };
  final ocrNoTok = await c.edge('ingest-ocr-reservation', ocrBody, jwt: c.buyerJwt);
  c.note('CEC.ocr-notoken', 'OCR sem x-device-token', ocrNoTok.brief, lens: 'CE8');
  if (ocrNoTok.ok) {
    c.hold(
      id: 'CEC.ocr-notoken',
      lens: 'CE8',
      severity: 'P0',
      title: 'OCR ingest sem device token',
      actor: 'buyer JWT',
      pre: 'ingest-ocr-reservation exige x-device-token',
      repro: 'POST functions/v1/ingest-ocr-reservation sem header',
      expected: '401 missing_device_token',
      obtained: ocrNoTok.brief,
    );
  } else {
    c.block('CEC.ocr-notoken', 'CE8', 'OCR sem token recusado', ocrNoTok.brief);
  }

  final ocrFake = await c.edge(
    'ingest-ocr-reservation',
    ocrBody,
    jwt: c.buyerJwt,
    extra: {'x-device-token': 'rtce-kicked-token-not-valid'},
  );
  c.note('CEC.ocr-fake', 'OCR token inventado', ocrFake.brief, lens: 'CE8');
  if (ocrFake.ok) {
    c.hold(
      id: 'CEC.ocr-fake',
      lens: 'CE8',
      severity: 'P0',
      title: 'OCR aceitou token inventado',
      actor: 'buyer JWT',
      pre: 'batata_validate_seller_device_token',
      repro: 'x-device-token=rtce-kicked-token-not-valid',
      expected: '401 invalid_token',
      obtained: ocrFake.brief,
    );
  } else {
    c.block('CEC.ocr-fake', 'CE8', 'OCR token fake recusado', ocrFake.brief);
  }

  final ocrReplay = await c.edge(
    'ingest-ocr-reservation',
    ocrBody,
    jwt: c.sellerJwt,
    extra: {'x-device-token': 'rtce-kicked-token-not-valid'},
  );
  c.note('CEC.ocr-replay', 'OCR replay token fake como seller', ocrReplay.brief,
      lens: 'CE8');
  if (ocrReplay.ok) {
    c.hold(
      id: 'CEC.ocr-replay',
      lens: 'CE8',
      severity: 'P1',
      title: 'OCR replay/token kick aceite',
      actor: 'seller JWT',
      pre: 'token revogado/inexistente',
      repro: 'mesmo body + token fake',
      expected: '401',
      obtained: ocrReplay.brief,
    );
  } else {
    c.block('CEC.ocr-replay', 'CE8', 'OCR replay recusado', ocrReplay.brief);
  }

  // ---- CE-D cronologia / inbox / cross-user ----
  final past = DateTime.now().toUtc().subtract(const Duration(hours: 3)).toIso8601String();
  final chrono = await c.postMsg(
    chatId: chatId,
    text: 'RTCE card no meio da timeline',
    jwt: c.buyerJwt,
    createdAt: past,
  );
  Map<String, dynamic>? chronoRow;
  if (chrono.firstId != null) {
    chronoRow = await c.msgRow(chrono.firstId!);
    c.createdMsgIds.add(chrono.firstId!);
  }
  final storedAt = '${chronoRow?['created_at']}';
  if (chrono.ok && storedAt.contains('202') && !storedAt.contains(DateTime.now().toUtc().toIso8601String().substring(0, 13))) {
    // if created_at honoured the past timestamp
    final honoured = storedAt.startsWith(past.substring(0, 16));
    if (honoured) {
      c.hold(
        id: 'CED.chrono-insert',
        lens: 'CE3',
        severity: 'P2',
        title: 'INSERT chat_messages com created_at no passado honrado',
        actor: 'buyer JWT',
        pre: 'guard_insert força created_at=now()',
        repro: 'POST chat_messages created_at=$past',
        expected: 'created_at = now()',
        obtained: storedAt,
      );
    } else {
      c.block('CED.chrono-insert', 'CE3', 'created_at forçado para now', storedAt);
    }
  } else {
    c.block('CED.chrono-insert', 'CE3', 'insert passado recusado ou now()', {
      'http': chrono.brief,
      'stored': storedAt,
    });
  }

  if (chrono.firstId != null) {
    final patchPast = await c.rest(
      'PATCH',
      'chat_messages?id=eq.${chrono.firstId}',
      jwt: c.buyerJwt,
      body: {'created_at': past},
    );
    final after = await c.msgRow(chrono.firstId!);
    final at2 = '${after?['created_at']}';
    if (patchPast.ok && at2.startsWith(past.substring(0, 16))) {
      c.hold(
        id: 'CED.chrono-patch',
        lens: 'CE3',
        severity: 'P2',
        title: 'PATCH created_at para o passado',
        actor: 'buyer JWT',
        pre: 'mensagens ordenadas por created_at',
        repro: 'PATCH chat_messages.created_at=$past',
        expected: 'rejeitado ou clamped now()',
        obtained: at2,
      );
    } else {
      c.block('CED.chrono-patch', 'CE3', 'PATCH created_at recusado/clamped', {
        'http': patchPast.brief,
        'stored': at2,
      });
    }
  }

  // 2.º buyer injeta no chat A–B
  final inject = await c.postMsg(
    chatId: chatId,
    text: 'B2 injeta no thread A-B',
    jwt: c.buyer2Jwt,
    sender: c.buyer2Id,
  );
  if (inject.ok && inject.firstId != null) {
    c.createdMsgIds.add(inject.firstId!);
    c.hold(
      id: 'CED.inject-b2',
      lens: 'CE7',
      severity: 'P0',
      title: 'B2 inseriu mensagem no chat A–B',
      actor: 'buyer2 JWT',
      pre: 'RLS chat_messages participantes',
      repro: 'POST chat_messages chat_id=A-B como B2',
      expected: '403/RLS',
      obtained: inject.brief,
    );
  } else {
    c.block('CED.inject-b2', 'CE7', 'inject B2 recusado', inject.brief);
  }

  final readAlien = await c.rest(
    'GET',
    'chat_messages?chat_id=eq.$chatId&select=id,text,sender_id&limit=5',
    jwt: c.buyer2Jwt,
  );
  if (readAlien.ok && readAlien.list.isNotEmpty) {
    c.hold(
      id: 'CED.read-thread',
      lens: 'CE5',
      severity: 'P1',
      title: 'B2 leu mensagens do thread A–B',
      actor: 'buyer2 JWT',
      pre: 'RLS select chat_messages',
      repro: 'GET chat_messages?chat_id=eq.{A-B}',
      expected: '[] / 403',
      obtained: readAlien.brief,
    );
  } else {
    c.block('CED.read-thread', 'CE5', 'read thread alheia recusada', readAlien.brief);
  }

  final inboxAlien = await c.rest(
    'PATCH',
    'chats?id=eq.$chatId',
    jwt: c.buyer2Jwt,
    body: {'last_message': 'WeChat Pay 12,00 €'},
  );
  final chatAfter = await c.chatRow(chatId);
  if (inboxAlien.ok && '${chatAfter?['last_message']}' == 'WeChat Pay 12,00 €') {
    c.hold(
      id: 'CED.inbox-alien',
      lens: 'CE5',
      severity: 'P1',
      title: 'B2 marcou/forjou last_message do chat A–B',
      actor: 'buyer2 JWT',
      pre: 'chats_update_participants',
      repro: 'PATCH chats.last_message como B2',
      expected: '403',
      obtained: {'http': inboxAlien.brief, 'stored': chatAfter?['last_message']},
    );
  } else {
    c.block('CED.inbox-alien', 'CE5', 'PATCH inbox alheio recusado', {
      'http': inboxAlien.brief,
      'stored': chatAfter?['last_message'],
    });
  }

  // ---- CE-E composição: rail mentiroso → tentar FSM pago / wallet ----
  final lie = await c.postMsg(
    chatId: paidA.chatId,
    text: jsonCard({
      'kind': 'reservation_payment_submitted',
      'order_id': oidA,
      'notes': 'WeChat Pay 12,00 €',
    }),
    jwt: c.buyerJwt,
  );
  final statusBefore = (await c.orderRow(oidA))?['status'];
  final patchPago = await c.patchOrder(oidA, {'status': 'pago'}, jwt: c.buyerJwt);
  final statusAfterBuyer = (await c.orderRow(oidA))?['status'];
  final patchPagoSeller =
      await c.patchOrder(oidA, {'status': 'pago'}, jwt: c.sellerJwt);
  final statusAfterSeller = (await c.orderRow(oidA))?['status'];
  final walAfter = await c.walletBal(c.sellerId);

  c.note('CEE.compose', 'WeChat card + PATCH pago', {
    'card': lie.brief,
    'before': statusBefore,
    'after_buyer_patch': statusAfterBuyer,
    'buyer_patch_http': patchPago.brief,
    'after_seller_patch': statusAfterSeller,
    'seller_patch_http': patchPagoSeller.brief,
    'wallet_before': walBefore,
    'wallet_after': walAfter,
  }, lens: 'CE1');

  final fsmMoved = statusAfterBuyer == 'pago' ||
      (statusBefore != 'pago' && statusAfterSeller == 'pago' && statusBefore != statusAfterSeller);
  // paidA is already pago from Stripe fixture — composition on pending oid
  final pendingStatus = (await c.orderRow(oid))?['status'];
  final pendingPatch = await c.patchOrder(oid, {'status': 'pago'}, jwt: c.buyerJwt);
  final pendingAfter = (await c.orderRow(oid))?['status'];
  c.note('CEE.pending', 'PATCH reserva_pendente → pago', {
    'before': pendingStatus,
    'http': pendingPatch.brief,
    'after': pendingAfter,
  }, lens: 'CE1');

  if (pendingAfter == 'pago' && pendingStatus != 'pago') {
    c.hold(
      id: 'CEE.fsm-pago',
      lens: 'CE1',
      severity: 'P0',
      title: 'Buyer passou encomenda a pago sem Stripe (composição rail/card)',
      actor: 'buyer JWT',
      pre: 'FSM pago só via Stripe webhook',
      repro: 'POST WeChat card + PATCH orders.status=pago',
      expected: 'status inalterado',
      obtained: {
        'before': pendingStatus,
        'after': pendingAfter,
        'http': pendingPatch.brief,
        'wallet_delta': walAfter - walBefore,
      },
    );
  } else {
    c.block('CEE.fsm-pago', 'CE1', 'FSM pago sem Stripe recusado', {
      'before': pendingStatus,
      'after': pendingAfter,
      'http': pendingPatch.brief,
    });
  }

  if (lie.ok && lie.firstId != null && pendingAfter != 'pago') {
    // card mentiroso persistiu mas FSM não mudou — já contado em pass1 se WeChat passar
    c.note('CEE.card-only', 'composição saturada: card sem FSM', lie.brief,
        lens: 'CE1');
  }

  await dumpJson('${outDir()}/pass2.json', {
    'pass': 2,
    'pocos': ['CE-B', 'CE-C', 'CE-D', 'CE-E'],
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
    'unused_guess': objB2guess,
    'fsm_moved_paidA': fsmMoved,
  });
  stdout.writeln('PASS2 findings=${c.findings.length} blocked=${c.blocked.length}');
}
