/// REDTEAM_BLIND_CK_CHAT_POS_CDCI_v1 — matriz CK-A/B/C/D.
/// Staging only. NÃO CORRIGIR. Anti-atrofia: rails FORA do exacto CDCI (Skrill/WeChat residual ≤2).
import 'dart:convert';
import 'dart:io';

import '_rtck.dart';

Future<void> main() async {
  final c = Rtck.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  final sku = await c.createProduct(title: '$prefix-cka', price: 12);
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
    stderr.writeln('fixture fail chat=$chatId oid=$oid paidA=$paidA paidB=$paidB');
    exit(4);
  }
  final paidTotal = (paidA.paidCents / 100).toStringAsFixed(2);
  final b = c.buyerId!;
  final oidA = paidA.oid;
  final oidB = paidB.oid;
  final walBefore = await c.walletBal(c.sellerId);

  final probes = <Map<String, dynamic>>[];

  void row({
    required String id,
    required String family,
    required String payload,
    required String http,
    required String bd,
    required String verdict,
    String? note,
  }) {
    probes.add({
      'id': id,
      'family': family,
      'payload': payload,
      'http': http,
      'bd': bd,
      'verdict': verdict,
      if (note != null) 'note': note,
    });
    stdout.writeln('PROBE $id [$verdict] $payload → $http | $bd');
  }

  Future<void> tryCard({
    required String id,
    required String lens,
    required Map<String, Object?> payload,
    required String family,
    String? title,
    bool residual = false,
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
    final orderId = payload['order_id']?.toString() ?? oid;
    final rowOrd = await c.orderRow(orderId);
    final status = '${rowOrd?['status']}';
    final label = title ??
        '${payload['kind']} ${(payload['notes'] ?? payload['label'] ?? payload['proof_url'] ?? '')}';
    if (persisted) {
      row(
        id: id,
        family: family,
        payload: label,
        http: '201 id=${h.firstId}',
        bd: 'orders.status=$status',
        verdict: residual ? 'HOLD_RESIDUAL' : 'FAIL',
        note: residual ? 'controlo CDCI exacto — não contar' : null,
      );
      if (!residual) {
        c.hold(
          id: id,
          lens: lens,
          severity: 'P1',
          title: label,
          actor: 'buyer JWT',
          pre: 'denylist/canonical CDCI sem este rail/encoding/URL',
          repro: 'POST chat_messages FLEABER_JSON_V1:${jsonEncode(payload)}',
          expected: 'notes_forbidden / url_denied / label_mismatch',
          obtained: h.brief,
          evidence: {
            'id': h.firstId,
            'kind': payload['kind'],
            'payload': payload,
            'order_status': status,
          },
        );
      } else {
        c.note(id, 'persistiu (residual CDCI, não contar)', h.brief, lens: lens);
      }
    } else {
      row(
        id: id,
        family: family,
        payload: label,
        http: h.brief,
        bd: 'orders.status=$status',
        verdict: 'HOLD',
      );
      c.block(id, lens, 'recusado', h.brief);
    }
  }

  Future<void> tryInbox(String id, String text, {bool residual = false}) async {
    final h = await c.rest(
      'PATCH',
      'chats?id=eq.$chatId',
      jwt: c.buyerJwt,
      body: {'last_message': text},
    );
    final chat = await c.chatRow(chatId);
    final stored = '${chat?['last_message']}';
    final persisted = h.ok && stored == text;
    if (persisted) {
      row(
        id: id,
        family: 'CK-C inbox',
        payload: 'PATCH last_message=$text',
        http: '${h.status}',
        bd: 'chats.last_message=$stored',
        verdict: residual ? 'HOLD_RESIDUAL' : 'FAIL',
        note: residual ? 'controlo CDCI exacto — não contar' : null,
      );
      if (!residual) {
        c.hold(
          id: id,
          lens: 'CK5',
          severity: 'P1',
          title: 'inbox last_message forjado: $text',
          actor: 'buyer JWT',
          pre: 'batata_chat_is_forged_inbox_preview CDCI',
          repro: 'PATCH chats.last_message=$text',
          expected: 'chat_inbox_preview_forbidden',
          obtained: stored,
        );
      } else {
        c.note(id, 'inbox residual persistiu (não contar)', stored, lens: 'CK5');
      }
    } else {
      row(
        id: id,
        family: 'CK-C inbox',
        payload: 'PATCH last_message=$text',
        http: h.brief,
        bd: 'chats.last_message=$stored',
        verdict: 'HOLD',
      );
      c.block(id, 'CK5', 'inbox recusado', {'http': h.brief, 'stored': stored});
    }
  }

  // ---- CK-A ≥24 strings + 2 à escolha (IT/DE) ----
  const oneDotLeader = '\u2024'; // ․
  final ckA = <String, String>{
    'paysafecash': 'PaysafeCash 12,00 €',
    'paysafe-cash-loja': 'PaySafe cash código loja',
    'pix-emv': 'Pix Copia e Cola 00020126580014BR.GOV.BCB.PIX0136a1b2c3d4',
    'pix-cpf': 'chave pix aleatória CPF 123.456.789-00',
    'picpay': 'PicPay 12,00 €',
    'mbway-qr': 'MB WAY QR / lê este QR MBWay',
    'sepa-inst': 'SEPA Instant / SCT Inst',
    'iban-instant': 'IBAN + enviado instantâneo 12 €',
    'revolut-dot-me': 'Revolut . Me 12,00 €',
    'revolut-u2024': 'revolut${oneDotLeader}me 12,00 €',
    'rev0lut': 'rev0lut.me 12 €',
    'apple-cash': 'Apple Cash 12,00 €',
    'apple-pay-cash': 'Apple Pay Cash',
    'tap-nfc': 'tap to cash / NFC prova',
    'gpay-send': 'Google Pay send money',
    'samsung-pay': 'Samsung Pay transfer',
    'money-order': 'money order / cashier check',
    'vanilla': 'Vanilla gift card',
    'paysafe-pin': 'PaySafe card PIN',
    'comprovativo-mbway-qr': 'comprovativo MB WAY QR',
    'transf-sepa': 'transferência imediata SEPA',
    'revolutme': 'enviei por RevolutMe',
    'cashapp-spaced': r'$Cash App Pay',
    'wise-tag': 'Wise tag @user / pay.wise',
    'it-bonifico': 'bonifico istantaneo 12,00 €',
    'de-ueberweisung': 'Überweisung 12,00 €',
  };

  for (final e in ckA.entries) {
    await tryCard(
      id: 'CKA.notes-${e.key}',
      lens: 'CK1',
      family: 'CK-A rails',
      title: 'card notes=${e.value}',
      payload: {
        'kind': 'reservation_payment_submitted',
        'order_id': oid,
        'notes': e.value,
      },
    );
  }

  // residual CDCI exactos — máx 2, não contar
  await tryCard(
    id: 'CKA.ctrl-skrill',
    lens: 'CK1',
    family: 'CK-A residual',
    residual: true,
    title: 'card notes=Skrill 12,00 €',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'Skrill 12,00 €',
    },
  );
  await tryCard(
    id: 'CKA.ctrl-wechat',
    lens: 'CK1',
    family: 'CK-A residual',
    residual: true,
    title: 'card notes=WeChat Pay 12,00 €',
    payload: {
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'WeChat Pay 12,00 €',
    },
  );

  // seguro (aplicável) — subset de rails novos
  for (final key in ['paysafecash', 'picpay', 'apple-cash', 'samsung-pay']) {
    await tryCard(
      id: 'CKA.seguro-$key',
      lens: 'CK1',
      family: 'CK-A seguro',
      chat: paidA.chatId,
      title: 'seguro_fleaber_paid label=${ckA[key]}',
      payload: {
        'kind': 'seguro_fleaber_paid',
        'order_id': paidA.oid,
        'total': paidTotal,
        'label': ckA[key],
      },
    );
  }

  // ---- CK-B ≥8 paths ----
  String absProof(String objectPath) =>
      '$stagingHost/storage/v1/object/fleaber_private/$objectPath';
  String proof(String uid, String orderId, String file) =>
      'order_proofs/$uid/$orderId/$file';

  final objA = proof(b, oidA, 'rtck_a.png');
  final upA = await c.storageUpload(
    objectName: objA,
    bytes: png1x1,
    jwt: c.buyerJwt,
  );
  c.note('CKC.upload-a', 'upload prova própria A', upA.brief, lens: 'CK6');

  final shy = '\u00AD';
  final twoDotLeader = '\u2025';
  final paths = <String, String>{
    'u002f':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/%u002e%u002e%u002f%u002e%u002e%u002forder_proofs/$b/$oidB/rtck_b.png',
    'pct255c':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/%2e%2e%255c%2e%2e%255corder_proofs/$b/$oidB/rtck_b.png',
    'utf16le':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/%ff%fe%2e%ff%fe%2e%ff%fe%2forder_proofs/$b/$oidB/rtck_b.png',
    'mixed-252f-255c':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/%252f%255c..%252f%255corder_proofs/$b/$oidB/rtck_b.png',
    'two-dot-leader':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/$twoDotLeader/$twoDotLeader/order_proofs/$b/$oidB/rtck_b.png',
    'c1-9c':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/%2e%2e%c1%9c%2e%2e%c1%9corder_proofs/$b/$oidB/rtck_b.png',
    'null-00':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/%2e%2e%00/%2e%2e/order_proofs/$b/$oidB/rtck_b.png',
    'shy-dots':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$b/$oidA/.$shy./.$shy./order_proofs/$b/$oidB/rtck_b.png',
  };

  for (final e in paths.entries) {
    await tryCard(
      id: 'CKB.proof-${e.key}',
      lens: 'CK2',
      family: 'CK-B path',
      title: 'proof_url ${e.key}',
      payload: {
        'kind': 'reservation_payment_submitted',
        'order_id': oidA,
        'notes': 'comprovativo envio',
        'proof_url': e.value,
      },
    );
  }

  // ---- CK-C inbox ≥4 rails novos ----
  await tryInbox('CKC.inbox-paysafecash', 'PaysafeCash 12,00 €');
  await tryInbox('CKC.inbox-tap-nfc', 'tap to cash / NFC prova');
  await tryInbox('CKC.inbox-samsung', 'Samsung Pay transfer');
  await tryInbox('CKC.inbox-vanilla', 'Vanilla gift card');
  await tryInbox('CKC.inbox-bonifico', 'bonifico istantaneo 12,00 €');
  await tryInbox('CKC.inbox-ueberweisung', 'Überweisung 12,00 €');
  await tryInbox('CKC.inbox-rev0lut', 'rev0lut.me 12 €');
  await tryInbox('CKC.ctrl-wechat', 'WeChat Pay 12,00 €', residual: true);

  // ---- CK-C storage alheio ≥2 ----
  final listAlien = await c.storageList(
    prefix: 'order_proofs/${c.buyer2Id}/',
    jwt: c.buyerJwt,
  );
  final listed = listAlien.list;
  if (listAlien.ok && listed.isNotEmpty) {
    row(
      id: 'CKC.list-alien',
      family: 'CK-C storage',
      payload: 'B1 LIST prefix order_proofs/{b2}/',
      http: listAlien.brief,
      bd: 'n=${listed.length}',
      verdict: 'FAIL',
    );
    c.hold(
      id: 'CKC.list-alien',
      lens: 'CK6',
      severity: 'P1',
      title: 'B1 listou objectos no prefixo de B2',
      actor: 'buyer JWT',
      pre: 'storage RLS fleaber_private',
      repro: 'POST /storage/v1/object/list/fleaber_private prefix=order_proofs/{b2}',
      expected: 'lista vazia / 4xx',
      obtained: listAlien.brief,
    );
  } else {
    row(
      id: 'CKC.list-alien',
      family: 'CK-C storage',
      payload: 'B1 LIST prefix order_proofs/{b2}/',
      http: listAlien.brief,
      bd: 'lista vazia/4xx',
      verdict: 'HOLD',
    );
    c.block('CKC.list-alien', 'CK6', 'list B2 recusado/vazio', listAlien.brief);
  }

  final upAlien = await c.storageUpload(
    objectName:
        'order_proofs/${c.buyer2Id}/00000000-0000-0000-0000-000000000099/x.png',
    bytes: png1x1,
    jwt: c.buyerJwt,
  );
  if (upAlien.ok) {
    row(
      id: 'CKC.upload-alien',
      family: 'CK-C storage',
      payload: 'B1 UPLOAD path B2',
      http: upAlien.brief,
      bd: 'object criado',
      verdict: 'FAIL',
    );
    c.hold(
      id: 'CKC.upload-alien',
      lens: 'CK6',
      severity: 'P0',
      title: 'B1 fez upload no path de B2',
      actor: 'buyer JWT',
      pre: 'storage insert RLS',
      repro: 'POST object/fleaber_private/order_proofs/{b2}/…',
      expected: '403/RLS',
      obtained: upAlien.brief,
    );
  } else {
    row(
      id: 'CKC.upload-alien',
      family: 'CK-C storage',
      payload: 'B1 UPLOAD path B2',
      http: upAlien.brief,
      bd: 'sem objecto',
      verdict: 'HOLD',
    );
    c.block('CKC.upload-alien', 'CK6', 'upload path B2 recusado', upAlien.brief);
  }

  // Extra storage (overwrite + GET) para lente CK6/CK7
  final getAasB2 = await c.storageGet(objA, jwt: c.buyer2Jwt);
  if (getAasB2.ok) {
    row(
      id: 'CKC.get-cross',
      family: 'CK-C storage',
      payload: 'B2 GET prova B1',
      http: getAasB2.brief,
      bd: 'leu objecto',
      verdict: 'FAIL',
    );
    c.hold(
      id: 'CKC.get-cross',
      lens: 'CK6',
      severity: 'P1',
      title: 'B2 leu prova de B1',
      actor: 'buyer2 JWT',
      pre: 'storage select RLS',
      repro: 'GET object/authenticated/fleaber_private/$objA',
      expected: '403',
      obtained: getAasB2.brief,
    );
  } else {
    row(
      id: 'CKC.get-cross',
      family: 'CK-C storage',
      payload: 'B2 GET prova B1',
      http: getAasB2.brief,
      bd: 'sem corpo',
      verdict: 'HOLD',
    );
    c.block('CKC.get-cross', 'CK6', 'GET prova alheia recusado', getAasB2.brief);
  }

  // ---- CK-D cronologia / cross-user (lentes CK3/CK7) ----
  final past =
      DateTime.now().toUtc().subtract(const Duration(hours: 3)).toIso8601String();
  final chrono = await c.postMsg(
    chatId: chatId,
    text: 'RTCK card no meio da timeline',
    jwt: c.buyerJwt,
    createdAt: past,
  );
  Map<String, dynamic>? chronoRow;
  if (chrono.firstId != null) {
    chronoRow = await c.msgRow(chrono.firstId!);
    c.createdMsgIds.add(chrono.firstId!);
  }
  final storedAt = '${chronoRow?['created_at']}';
  final honoured = chrono.ok && storedAt.startsWith(past.substring(0, 16));
  if (honoured) {
    row(
      id: 'CKD.chrono-insert',
      family: 'CK-D chrono',
      payload: 'INSERT created_at=$past',
      http: chrono.brief,
      bd: 'created_at=$storedAt',
      verdict: 'FAIL',
    );
    c.hold(
      id: 'CKD.chrono-insert',
      lens: 'CK3',
      severity: 'P2',
      title: 'INSERT chat_messages com created_at no passado honrado',
      actor: 'buyer JWT',
      pre: 'guard força created_at=now()',
      repro: 'POST chat_messages created_at=$past',
      expected: 'created_at = now()',
      obtained: storedAt,
    );
  } else {
    row(
      id: 'CKD.chrono-insert',
      family: 'CK-D chrono',
      payload: 'INSERT created_at=$past',
      http: chrono.brief,
      bd: 'created_at=$storedAt',
      verdict: 'HOLD',
    );
    c.block('CKD.chrono-insert', 'CK3', 'created_at forçado para now', {
      'http': chrono.brief,
      'stored': storedAt,
    });
  }

  final inject = await c.postMsg(
    chatId: chatId,
    text: 'B2 injeta no thread A-B',
    jwt: c.buyer2Jwt,
    sender: c.buyer2Id,
  );
  if (inject.ok && inject.firstId != null) {
    c.createdMsgIds.add(inject.firstId!);
    row(
      id: 'CKD.inject-b2',
      family: 'CK-D cross-user',
      payload: 'B2 INSERT chat A-B',
      http: inject.brief,
      bd: 'msg id=${inject.firstId}',
      verdict: 'FAIL',
    );
    c.hold(
      id: 'CKD.inject-b2',
      lens: 'CK7',
      severity: 'P0',
      title: 'B2 inseriu mensagem no chat A–B',
      actor: 'buyer2 JWT',
      pre: 'RLS chat_messages participantes',
      repro: 'POST chat_messages chat_id=A-B como B2',
      expected: '403/RLS',
      obtained: inject.brief,
    );
  } else {
    row(
      id: 'CKD.inject-b2',
      family: 'CK-D cross-user',
      payload: 'B2 INSERT chat A-B',
      http: inject.brief,
      bd: '0 rows',
      verdict: 'HOLD',
    );
    c.block('CKD.inject-b2', 'CK7', 'inject B2 recusado', inject.brief);
  }

  // ---- CK8 Edge/OCR ----
  final ocrBody = {
    'live_id': '00000000-0000-0000-0000-000000000001',
    'ocr_line_hash': 'rtck1316deadbeef',
    'detected_at': DateTime.now().toUtc().toIso8601String(),
    'ocr_raw_line': 'PaysafeCash confirmado 12,00 €',
    'ref_number': 1,
    'external_display_name': 'RTCK',
  };
  final ocrNoTok = await c.edge('ingest-ocr-reservation', ocrBody, jwt: c.buyerJwt);
  if (ocrNoTok.ok) {
    row(
      id: 'CK8.ocr-notoken',
      family: 'CK8 Edge',
      payload: 'OCR sem x-device-token',
      http: ocrNoTok.brief,
      bd: 'ingest ok',
      verdict: 'FAIL',
    );
    c.hold(
      id: 'CK8.ocr-notoken',
      lens: 'CK8',
      severity: 'P0',
      title: 'OCR ingest sem device token',
      actor: 'buyer JWT',
      pre: 'exige x-device-token',
      repro: 'POST ingest-ocr-reservation sem header',
      expected: '401 missing_device_token',
      obtained: ocrNoTok.brief,
    );
  } else {
    row(
      id: 'CK8.ocr-notoken',
      family: 'CK8 Edge',
      payload: 'OCR sem x-device-token',
      http: ocrNoTok.brief,
      bd: 'sem ingest',
      verdict: 'HOLD',
    );
    c.block('CK8.ocr-notoken', 'CK8', 'OCR sem token recusado', ocrNoTok.brief);
  }

  // ---- CK-D composição card novo rail → PATCH pago ----
  final lieRail = 'PaysafeCash 12,00 €';
  final lie = await c.postMsg(
    chatId: chatId,
    text: jsonCard({
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': lieRail,
    }),
    jwt: c.buyerJwt,
  );
  final pendingStatus = (await c.orderRow(oid))?['status'];
  final pendingPatch =
      await c.patchOrder(oid, {'status': 'pago'}, jwt: c.buyerJwt);
  final pendingAfter = (await c.orderRow(oid))?['status'];
  final walAfter = await c.walletBal(c.sellerId);
  final fsmMoved = pendingAfter == 'pago' && pendingStatus != 'pago';
  row(
    id: 'CKD.compose-pago',
    family: 'CK-D composição',
    payload: 'card $lieRail + PATCH status=pago',
    http: 'card=${lie.brief} patch=${pendingPatch.brief}',
    bd: 'status $pendingStatus → $pendingAfter wallet $walBefore → $walAfter',
    verdict: fsmMoved ? 'FAIL' : 'HOLD',
  );
  if (fsmMoved) {
    c.hold(
      id: 'CKD.compose-pago',
      lens: 'CK1',
      severity: 'P0',
      title: 'Buyer passou encomenda a pago sem Stripe (composição rail)',
      actor: 'buyer JWT',
      pre: 'FSM pago só via Stripe webhook',
      repro: 'POST PaysafeCash card + PATCH orders.status=pago',
      expected: 'status inalterado',
      obtained: {
        'before': pendingStatus,
        'after': pendingAfter,
        'http': pendingPatch.brief,
        'wallet_delta': walAfter - walBefore,
      },
    );
  } else {
    c.block('CKD.compose-pago', 'CK1', 'FSM pago sem Stripe recusado', {
      'card': lie.brief,
      'before': pendingStatus,
      'after': pendingAfter,
      'http': pendingPatch.brief,
      'wallet_delta': walAfter - walBefore,
    });
  }

  await dumpJson('${outDir()}/probes.json', {
    'auditor': 'REDTEAM_BLIND_CK_CHAT_POS_CDCI_v1',
    'prefix': prefix,
    'probes': probes,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
    'chat_id': chatId,
    'order_pending': oid,
    'order_paid_a': oidA,
    'order_paid_b': oidB,
    'unused_abs': absProof(objA),
  });
  stdout.writeln(
    'DONE probes=${probes.length} findings=${c.findings.length} blocked=${c.blocked.length} lenses=${c.lensesHit.toList()..sort()}',
  );
}
