/// REDTEAM_BLIND_CQ_CHAT_POS_ALLOW_v1 — bypass allowlist notes/label/inbox.
/// Staging only. NÃO CORRIGIR. Residual PaysafeCash/PicPay exactos ≤2.
import 'dart:convert';
import 'dart:io';

import '_rtcq.dart';

Future<void> main() async {
  final c = Rtcq.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  final sku = await c.createProduct(title: '$prefix-cqa', price: 12);
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
  if (chatId == null || oid == null || paidA == null) {
    stderr.writeln('fixture fail chat=$chatId oid=$oid paid=${paidA?.oid}');
    exit(4);
  }
  final paidOid = paidA.oid;
  final walBefore = await c.walletBal(c.sellerId);

  final probes = <Map<String, dynamic>>[];

  void row({
    required String id,
    required String surface,
    required String payload,
    required String http,
    required String bd,
    required String verdict,
    String? note,
  }) {
    probes.add({
      'probe_id': id,
      'superfície': surface,
      'payload': payload,
      'http_rpc': http,
      'bd_inbox': bd,
      'verdict': verdict,
      if (note != null) 'note': note,
    });
    stdout.writeln('PROBE $id [$verdict] $payload → $http | $bd');
  }

  bool looksDenied(HttpHit h) {
    final raw = h.body.toLowerCase();
    return !h.ok ||
        raw.contains('forbidden') ||
        raw.contains('mismatch') ||
        raw.contains('23514') ||
        raw.contains('54000') ||
        raw.contains('42501');
  }

  Future<HttpHit> postCard(Map<String, Object?> payload, {String? jwt}) {
    return c.postMsg(
      chatId: chatId,
      text: jsonCard(payload),
      jwt: jwt ?? c.buyerJwt,
    );
  }

  Future<void> tryNotes({
    required String id,
    required String lens,
    required String notes,
    required String family,
    bool expectAllow = false,
    bool residual = false,
  }) async {
    final payload = <String, Object?>{
      'kind': 'reservation_payment_submitted',
      'order_id': paidOid,
      'notes': notes,
    };
    final h = await postCard(payload);
    final persisted = h.ok && h.firstId != null;
    if (persisted && h.firstId != null) c.createdMsgIds.add(h.firstId!);
    final status = '${(await c.orderRow(paidOid))?['status']}';
    if (residual) {
      row(
        id: id,
        surface: family,
        payload: notes,
        http: persisted ? '201 id=${h.firstId}' : h.brief,
        bd: 'orders.status=$status',
        verdict: persisted ? 'HOLD_RESIDUAL' : 'HOLD',
        note: 'controlo residual exacto — não contar',
      );
      c.note(id, residual ? 'residual exacto' : 'residual', h.brief, lens: lens);
      return;
    }
    if (expectAllow) {
      if (persisted) {
        row(
          id: id,
          surface: family,
          payload: notes.isEmpty ? '(vazio)' : notes,
          http: '201 id=${h.firstId}',
          bd: 'orders.status=$status · notes persistidas',
          verdict: 'PASS',
        );
        c.block(id, lens, 'allowlist aceitou texto legítimo', h.brief);
      } else {
        row(
          id: id,
          surface: family,
          payload: notes.isEmpty ? '(vazio)' : notes,
          http: h.brief,
          bd: 'orders.status=$status · recusado',
          verdict: 'FAIL',
        );
        c.hold(
          id: id,
          lens: lens,
          severity: 'P2',
          title: 'allowlist recusou texto legítimo: ${notes.isEmpty ? "(vazio)" : notes}',
          actor: 'buyer JWT',
          pre: 'vazio / stripe_paid_direct / texto livre sem €/montante deve passar',
          repro: 'POST reservation_payment_submitted notes=${jsonEncode(notes)}',
          expected: '201',
          obtained: h.brief,
        );
      }
      return;
    }
    if (persisted) {
      row(
        id: id,
        surface: family,
        payload: notes,
        http: '201 id=${h.firstId}',
        bd: 'orders.status=$status · notes persistidas',
        verdict: 'FAIL',
      );
      c.hold(
        id: id,
        lens: lens,
        severity: 'P1',
        title: 'notes fora da allowlist persistiram: $notes',
        actor: 'buyer JWT',
        pre: 'batata_chat_client_notes_allowed deve recusar montante/€/encoding',
        repro: 'POST reservation_payment_submitted notes=${jsonEncode(notes)}',
        expected: 'notes_forbidden / 4xx',
        obtained: h.brief,
        evidence: {'id': h.firstId, 'notes': notes, 'order_status': status},
      );
    } else {
      row(
        id: id,
        surface: family,
        payload: notes,
        http: h.brief,
        bd: 'orders.status=$status · recusado',
        verdict: 'HOLD',
      );
      c.block(id, lens, 'notes recusadas', h.brief);
    }
  }

  Future<void> trySeguro({
    required String id,
    required String lens,
    required String label,
    required String family,
    bool expectAllow = false,
  }) async {
    final h = await postCard({
      'kind': 'seguro_fleaber_paid',
      'order_id': paidOid,
      'label': label,
    });
    final persisted = h.ok && h.firstId != null;
    if (persisted && h.firstId != null) c.createdMsgIds.add(h.firstId!);
    final status = '${(await c.orderRow(paidOid))?['status']}';
    if (expectAllow) {
      if (persisted) {
        row(
          id: id,
          surface: family,
          payload: label.isEmpty ? '(label vazio)' : label,
          http: '201 id=${h.firstId}',
          bd: 'orders.status=$status',
          verdict: 'PASS',
        );
        c.block(id, lens, 'label allowlist aceitou', h.brief);
      } else {
        row(
          id: id,
          surface: family,
          payload: label.isEmpty ? '(label vazio)' : label,
          http: h.brief,
          bd: 'orders.status=$status',
          verdict: 'FAIL',
        );
        c.hold(
          id: id,
          lens: lens,
          severity: 'P2',
          title: 'seguro recusou label canónico: $label',
          actor: 'buyer JWT',
          pre: 'batata_chat_seguro_label_allowed',
          repro: 'POST seguro_fleaber_paid label=${jsonEncode(label)}',
          expected: '201',
          obtained: h.brief,
        );
      }
      return;
    }
    if (persisted) {
      row(
        id: id,
        surface: family,
        payload: label,
        http: '201 id=${h.firstId}',
        bd: 'orders.status=$status · label persistido',
        verdict: 'FAIL',
      );
      c.hold(
        id: id,
        lens: lens,
        severity: 'P1',
        title: 'seguro label fora da allowlist: $label',
        actor: 'buyer JWT',
        pre: 'só 4 labels canónicas + vazio',
        repro: 'POST seguro_fleaber_paid label=${jsonEncode(label)}',
        expected: 'label_mismatch',
        obtained: h.brief,
        evidence: {'id': h.firstId, 'label': label},
      );
    } else {
      row(
        id: id,
        surface: family,
        payload: label,
        http: h.brief,
        bd: 'orders.status=$status · recusado',
        verdict: 'HOLD',
      );
      c.block(id, lens, 'seguro label recusado', h.brief);
    }
  }

  Future<void> tryInbox({
    required String id,
    required String lens,
    required String text,
    bool residual = false,
  }) async {
    final h = await c.rest(
      'PATCH',
      'chats?id=eq.$chatId',
      jwt: c.buyerJwt,
      body: {'last_message': text},
    );
    final chat = await c.chatRow(chatId);
    final stored = '${chat?['last_message']}';
    final persisted = h.ok && stored == text;
    if (residual) {
      row(
        id: id,
        surface: 'CQ-C inbox',
        payload: text,
        http: '${h.status}',
        bd: 'chats.last_message=$stored',
        verdict: persisted ? 'HOLD_RESIDUAL' : 'HOLD',
        note: 'controlo residual exacto — não contar',
      );
      c.note(id, 'inbox residual', {'http': h.brief, 'stored': stored},
          lens: lens);
      return;
    }
    if (persisted) {
      row(
        id: id,
        surface: 'CQ-C inbox',
        payload: text,
        http: '${h.status}',
        bd: 'chats.last_message stored exact',
        verdict: 'FAIL',
      );
      c.hold(
        id: id,
        lens: lens,
        severity: 'P1',
        title: 'inbox last_message bypass allowlist: $text',
        actor: 'buyer JWT',
        pre: 'batata_chat_is_forged_inbox_preview + notes allowlist',
        repro: 'PATCH chats.last_message=${jsonEncode(text)}',
        expected: 'chat_inbox_preview_forbidden',
        obtained: stored,
      );
    } else {
      row(
        id: id,
        surface: 'CQ-C inbox',
        payload: text,
        http: h.brief,
        bd: 'chats.last_message=$stored',
        verdict: 'HOLD',
      );
      c.block(id, lens, 'inbox recusado',
          {'http': h.brief, 'stored': stored});
    }
  }

  // ---- CQ-A positivos (≥3) ----
  await tryNotes(
    id: 'CQA.A1-empty',
    lens: 'CQ1',
    notes: '',
    family: 'CQ-A notes',
    expectAllow: true,
  );
  await tryNotes(
    id: 'CQA.A2-stripe',
    lens: 'CQ1',
    notes: 'stripe_paid_direct',
    family: 'CQ-A notes',
    expectAllow: true,
  );
  await tryNotes(
    id: 'CQA.A3-obrigado',
    lens: 'CQ1',
    notes: 'obrigado',
    family: 'CQ-A notes',
    expectAllow: true,
  );
  await tryNotes(
    id: 'CQA.A3b-ja-enviei',
    lens: 'CQ1',
    notes: 'já enviei',
    family: 'CQ-A notes',
    expectAllow: true,
  );

  // ---- CQ-B bypass allowlist (≥8) ----
  const euro = '\u20AC'; // €
  const yenFw = '\uFFE5'; // ￥
  const euroBank = '\u{1F4B6}'; // 💶
  const zwsp = '\u200B';
  const shy = '\u00AD';
  const greekEps = '\u03F5'; // ϵ
  const euroCurr = '\u20A0'; // ₠
  const pad =
      'segue o comprovativo em anexo conforme combinado ontem à noite e ';

  await tryNotes(
    id: 'CQB.B1-euro-unicode',
    lens: 'CQ2',
    notes: 'obrigado $euro',
    family: 'CQ-B encoding',
  );
  await tryNotes(
    id: 'CQB.B1b-yen-fullwidth',
    lens: 'CQ2',
    notes: 'obrigado $yenFw 12',
    family: 'CQ-B encoding',
  );
  await tryNotes(
    id: 'CQB.B1c-euro-emoji',
    lens: 'CQ3',
    notes: 'enviado 12 $euroBank',
    family: 'CQ-B encoding',
  );
  await tryNotes(
    id: 'CQB.B2-amount-no-rail',
    lens: 'CQ3',
    notes: '12,00',
    family: 'CQ-B amount',
  );
  await tryNotes(
    id: 'CQB.B2b-dot-eur',
    lens: 'CQ3',
    notes: '12.00 EUR',
    family: 'CQ-B amount',
  );
  await tryNotes(
    id: 'CQB.B2c-doze-euros',
    lens: 'CQ3',
    notes: 'doze euros',
    family: 'CQ-B amount',
  );
  await tryNotes(
    id: 'CQB.B3-zwsp-amount',
    lens: 'CQ2',
    notes: '12${zwsp},00 $euro',
    family: 'CQ-B encoding',
  );
  await tryNotes(
    id: 'CQB.B3b-shy-amount',
    lens: 'CQ2',
    notes: '12${shy},00 EUR',
    family: 'CQ-B encoding',
  );
  await tryNotes(
    id: 'CQB.B4-homoglyph-eps',
    lens: 'CQ2',
    notes: '12,00 $greekEps',
    family: 'CQ-B encoding',
  );
  await tryNotes(
    id: 'CQB.B4b-euro-currency-sign',
    lens: 'CQ2',
    notes: '12 $euroCurr',
    family: 'CQ-B encoding',
  );
  await tryNotes(
    id: 'CQB.B4c-fullwidth-eur',
    lens: 'CQ2',
    notes: '１２．００ ＥＵＲ',
    family: 'CQ-B encoding',
  );
  await tryNotes(
    id: 'CQB.B5-digits-comma',
    lens: 'CQ3',
    notes: '12,50',
    family: 'CQ-B amount',
  );
  await tryNotes(
    id: 'CQB.B6-html-entity',
    lens: 'CQ2',
    notes: 'paguei &#8364; 12',
    family: 'CQ-B encoding',
  );
  await tryNotes(
    id: 'CQB.B6b-amp-euro',
    lens: 'CQ2',
    notes: '12 &euro;',
    family: 'CQ-B encoding',
  );
  await tryNotes(
    id: 'CQB.B7-json-array',
    lens: 'CQ6',
    notes: '["12,00"]',
    family: 'CQ-B json',
  );
  await tryNotes(
    id: 'CQB.B7b-json-object',
    lens: 'CQ6',
    notes: '{"paid":12.00}',
    family: 'CQ-B json',
  );
  await tryNotes(
    id: 'CQB.B8-long-mid-amount',
    lens: 'CQ3',
    notes: '${pad}12,00 no meio do texto combinado',
    family: 'CQ-B amount',
  );

  // Residual exact (≤2) — não contar
  await tryNotes(
    id: 'CQB.R-paysafecash',
    lens: 'CQ1',
    notes: 'PaysafeCash 12,00 €',
    family: 'CQ-B residual',
    residual: true,
  );

  // ---- CQ-C label + inbox + card + storage + compose ----
  await trySeguro(
    id: 'CQC.C1-seguro-hostile',
    lens: 'CQ4',
    label: 'compra paga 12,00 $euro',
    family: 'CQ-C seguro',
  );
  await trySeguro(
    id: 'CQC.C1b-paguei-as-label',
    lens: 'CQ4',
    label: 'paguei',
    family: 'CQ-C seguro',
  );
  await trySeguro(
    id: 'CQC.C1c-canonical',
    lens: 'CQ4',
    label: 'compra paga',
    family: 'CQ-C seguro',
    expectAllow: true,
  );

  await tryInbox(
    id: 'CQC.C2-inbox-amount',
    lens: 'CQ5',
    text: '12,00',
  );
  await tryInbox(
    id: 'CQC.C2b-inbox-entity',
    lens: 'CQ5',
    text: '12 &euro;',
  );
  await tryInbox(
    id: 'CQC.C2c-inbox-emoji',
    lens: 'CQ5',
    text: 'enviado 12 $euroBank',
  );
  await tryInbox(
    id: 'CQC.C2d-inbox-doze',
    lens: 'CQ5',
    text: 'doze euros',
  );

  await tryNotes(
    id: 'CQC.C3-card-hostile',
    lens: 'CQ6',
    notes: 'pago 12 usd',
    family: 'CQ-C card',
  );

  // C4 storage alheio (1)
  final upAlien = await c.storageUpload(
    objectName:
        'order_proofs/${c.buyer2Id}/00000000-0000-0000-0000-000000000099/x.png',
    bytes: png1x1,
    jwt: c.buyerJwt,
  );
  if (upAlien.ok) {
    row(
      id: 'CQC.C4-upload-alien',
      surface: 'CQ-C storage',
      payload: 'B1 UPLOAD path B2',
      http: upAlien.brief,
      bd: 'object criado',
      verdict: 'FAIL',
    );
    c.hold(
      id: 'CQC.C4-upload-alien',
      lens: 'CQ6',
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
      id: 'CQC.C4-upload-alien',
      surface: 'CQ-C storage',
      payload: 'B1 UPLOAD path B2',
      http: upAlien.brief,
      bd: 'sem objecto',
      verdict: 'HOLD',
    );
    c.block('CQC.C4-upload-alien', 'CQ6', 'upload path B2 recusado',
        upAlien.brief);
  }

  // C5 composição card → PATCH pago (sem Stripe)
  final lieNotes = '12,00';
  final lie = await postCard({
    'kind': 'reservation_payment_submitted',
    'order_id': oid,
    'notes': lieNotes,
  });
  if (lie.firstId != null) c.createdMsgIds.add(lie.firstId!);
  final pendingStatus = (await c.orderRow(oid))?['status'];
  final pendingPatch =
      await c.patchOrder(oid, {'status': 'pago'}, jwt: c.buyerJwt);
  final pendingAfter = (await c.orderRow(oid))?['status'];
  final walAfter = await c.walletBal(c.sellerId);
  final fsmMoved = pendingAfter == 'pago' && pendingStatus != 'pago';
  row(
    id: 'CQC.C5-compose-pago',
    surface: 'CQ-C composição',
    payload: 'card notes=$lieNotes + PATCH status=pago',
    http: 'card=${lie.brief} patch=${pendingPatch.brief}',
    bd: 'status $pendingStatus → $pendingAfter wallet $walBefore → $walAfter',
    verdict: fsmMoved ? 'FAIL' : 'HOLD',
  );
  if (fsmMoved) {
    c.hold(
      id: 'CQC.C5-compose-pago',
      lens: 'CQ6',
      severity: 'P0',
      title: 'Buyer passou encomenda a pago sem Stripe (notes allowlist bypass)',
      actor: 'buyer JWT',
      pre: 'FSM pago só via Stripe webhook',
      repro: 'POST card notes=12,00 + PATCH orders.status=pago',
      expected: 'status inalterado',
      obtained: {
        'before': pendingStatus,
        'after': pendingAfter,
        'http': pendingPatch.brief,
        'wallet_delta': walAfter - walBefore,
      },
    );
  } else {
    c.block('CQC.C5-compose-pago', 'CQ6', 'FSM pago sem Stripe recusado', {
      'card': lie.brief,
      'before': pendingStatus,
      'after': pendingAfter,
      'http': pendingPatch.brief,
      'wallet_delta': walAfter - walBefore,
    });
  }

  // CQ7 Edge — OCR sem token (não é rail list)
  final ocr = await c.edge('ingest-ocr-reservation', {
    'live_id': '00000000-0000-0000-0000-000000000001',
    'ocr_line_hash': 'rtcq1412deadbeef',
    'detected_at': DateTime.now().toUtc().toIso8601String(),
    'ocr_raw_line': '12,00 confirmado',
    'ref_number': 1,
    'external_display_name': 'RTCQ',
  }, jwt: c.buyerJwt);
  if (ocr.ok) {
    row(
      id: 'CQ7.ocr-notoken',
      surface: 'CQ7 Edge',
      payload: 'OCR sem x-device-token ocr_raw=12,00 confirmado',
      http: ocr.brief,
      bd: 'ingest ok',
      verdict: 'FAIL',
    );
    c.hold(
      id: 'CQ7.ocr-notoken',
      lens: 'CQ7',
      severity: 'P0',
      title: 'OCR ingest sem device token',
      actor: 'buyer JWT',
      pre: 'exige x-device-token',
      repro: 'POST ingest-ocr-reservation sem header',
      expected: '401 missing_device_token',
      obtained: ocr.brief,
    );
  } else {
    row(
      id: 'CQ7.ocr-notoken',
      surface: 'CQ7 Edge',
      payload: 'OCR sem x-device-token ocr_raw=12,00 confirmado',
      http: ocr.brief,
      bd: 'sem ingest',
      verdict: 'HOLD',
    );
    c.block('CQ7.ocr-notoken', 'CQ7', 'OCR sem token recusado', ocr.brief);
  }

  // Extra: notes as JSON number via raw card (kind + numeric notes)
  final numNotes = await postCard({
    'kind': 'reservation_payment_submitted',
    'order_id': paidOid,
    'notes': 12.00,
  });
  final numPersisted = numNotes.ok && numNotes.firstId != null;
  if (numPersisted && numNotes.firstId != null) {
    c.createdMsgIds.add(numNotes.firstId!);
  }
  row(
    id: 'CQB.B7c-notes-number',
    surface: 'CQ-B json',
    payload: 'notes=12.00 (JSON number)',
    http: numPersisted ? '201 id=${numNotes.firstId}' : numNotes.brief,
    bd: 'card ${numPersisted ? "persistido" : "recusado"}',
    verdict: numPersisted ? 'FAIL' : 'HOLD',
  );
  if (numPersisted) {
    c.hold(
      id: 'CQB.B7c-notes-number',
      lens: 'CQ6',
      severity: 'P1',
      title: 'notes JSON number 12.00 persistiu',
      actor: 'buyer JWT',
      pre: 'allowlist trata notes como texto; number não deve passar como montante',
      repro: 'POST notes: 12.00 (JSON number)',
      expected: 'notes_forbidden',
      obtained: numNotes.brief,
    );
  } else {
    c.block('CQB.B7c-notes-number', 'CQ6', 'notes number recusado',
        numNotes.brief);
  }

  final residualN =
      probes.where((p) => p['verdict'] == 'HOLD_RESIDUAL').length;
  final liveN = probes.length;
  final atrofia = liveN > 0 && residualN / liveN >= 0.5;

  await dumpJson('${outDir()}/probes.json', {
    'auditor': 'REDTEAM_BLIND_CQ_CHAT_POS_ALLOW_v1',
    'prefix': prefix,
    'probes': probes,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
    'chat_id': chatId,
    'order_pending': oid,
    'order_paid_a': paidOid,
    'wallet_before': walBefore,
    'wallet_after': walAfter,
    'residual_count': residualN,
    'probes_na_tabela': liveN,
    'atrofia': atrofia,
    'denied_helper_unused': looksDenied(numNotes),
  });
  stdout.writeln(
    'DONE probes=${probes.length} findings=${c.findings.length} '
    'blocked=${c.blocked.length} residual=$residualN atrofia=$atrofia '
    'lenses=${c.lensesHit.toList()..sort()}',
  );
}
