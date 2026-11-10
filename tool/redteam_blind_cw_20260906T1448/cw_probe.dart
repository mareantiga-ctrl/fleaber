/// REDTEAM_BLIND_CW_CHAT_POS_CPCU_v1 — bypass allowlist estrita notes/label/inbox.
/// Staging only. NÃO CORRIGIR. Residual CQ exacto (12,00 · doze euros · &euro;) ≤2 se HOLD.
import 'dart:convert';
import 'dart:io';

import '_rtcw.dart';

Future<void> main() async {
  final c = Rtcw.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  final sku = await c.createProduct(title: '$prefix-cwa', price: 12);
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
    String? payloadLabel,
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
    final shown = payloadLabel ?? (notes.isEmpty ? '(vazio)' : notes);
    if (residual) {
      row(
        id: id,
        surface: family,
        payload: shown,
        http: persisted ? '201 id=${h.firstId}' : h.brief,
        bd: 'orders.status=$status',
        verdict: persisted ? 'HOLD_RESIDUAL' : 'HOLD',
        note: 'controlo residual exacto CQ — não contar',
      );
      c.note(id, 'residual exacto CQ', h.brief, lens: lens);
      return;
    }
    if (expectAllow) {
      if (persisted) {
        row(
          id: id,
          surface: family,
          payload: shown,
          http: '201 id=${h.firstId}',
          bd: 'orders.status=$status · notes persistidas',
          verdict: 'PASS',
        );
        c.block(id, lens, 'allowlist aceitou canónico', h.brief);
      } else {
        row(
          id: id,
          surface: family,
          payload: shown,
          http: h.brief,
          bd: 'orders.status=$status · recusado',
          verdict: 'FAIL',
        );
        c.hold(
          id: id,
          lens: lens,
          severity: 'P2',
          title: 'allowlist recusou canónico: $shown',
          actor: 'buyer JWT',
          pre: 'vazio / stripe_paid_direct / ok / paguei / pago / comprovativo / obrigado / já enviei / frase longa',
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
        payload: shown,
        http: '201 id=${h.firstId}',
        bd: 'orders.status=$status · notes persistidas',
        verdict: 'FAIL',
      );
      c.hold(
        id: id,
        lens: lens,
        severity: 'P1',
        title: 'notes fora da allowlist estrita persistiram: $shown',
        actor: 'buyer JWT',
        pre: 'só tokens canónicos exactos após lower(trim); resto deny mesmo sem €',
        repro: 'POST reservation_payment_submitted notes=${jsonEncode(notes)}',
        expected: 'notes_forbidden / 4xx',
        obtained: h.brief,
        evidence: {'id': h.firstId, 'notes': notes, 'order_status': status},
      );
    } else {
      row(
        id: id,
        surface: family,
        payload: shown,
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
          verdict: 'HOLD',
          note: 'guarda total/outro — não é bypass notes',
        );
        c.block(id, lens, 'seguro canónico recusado por outro guarda', h.brief);
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
    bool expectAllow = false,
    String? payloadLabel,
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
    final shown = payloadLabel ?? text;
    if (residual) {
      row(
        id: id,
        surface: 'CW-C inbox',
        payload: shown,
        http: '${h.status}',
        bd: 'chats.last_message=$stored',
        verdict: persisted ? 'HOLD_RESIDUAL' : 'HOLD',
        note: 'controlo residual exacto CQ — não contar',
      );
      c.note(id, 'inbox residual CQ', {'http': h.brief, 'stored': stored},
          lens: lens);
      return;
    }
    if (expectAllow) {
      if (persisted) {
        row(
          id: id,
          surface: 'CW-C inbox',
          payload: shown,
          http: '${h.status}',
          bd: 'chats.last_message stored exact',
          verdict: 'PASS',
        );
        c.block(id, lens, 'inbox canónico aceite', stored);
      } else {
        row(
          id: id,
          surface: 'CW-C inbox',
          payload: shown,
          http: h.brief,
          bd: 'chats.last_message=$stored',
          verdict: 'FAIL',
        );
        c.hold(
          id: id,
          lens: lens,
          severity: 'P2',
          title: 'inbox recusou canónico: $shown',
          actor: 'buyer JWT',
          pre: 'preview canónico deve passar notes_allowed',
          repro: 'PATCH chats.last_message=${jsonEncode(text)}',
          expected: '200 stored exact',
          obtained: stored,
        );
      }
      return;
    }
    if (persisted) {
      row(
        id: id,
        surface: 'CW-C inbox',
        payload: shown,
        http: '${h.status}',
        bd: 'chats.last_message stored exact',
        verdict: 'FAIL',
      );
      c.hold(
        id: id,
        lens: lens,
        severity: 'P1',
        title: 'inbox last_message bypass allowlist estrita: $shown',
        actor: 'buyer JWT',
        pre: 'forged_inbox = qualquer preview não canónico',
        repro: 'PATCH chats.last_message=${jsonEncode(text)}',
        expected: 'chat_inbox_preview_forbidden',
        obtained: stored,
      );
    } else {
      row(
        id: id,
        surface: 'CW-C inbox',
        payload: shown,
        http: h.brief,
        bd: 'chats.last_message=$stored',
        verdict: 'HOLD',
      );
      c.block(id, lens, 'inbox recusado',
          {'http': h.brief, 'stored': stored});
    }
  }

  const zwsp = '\u200B';
  const nbsp = '\u00A0';
  const rlo = '\u202E';
  const euroBank = '\u{1F4B6}'; // 💶

  // ---- CW-A positivos (≥4) ----
  await tryNotes(
    id: 'CWA.A1-empty',
    lens: 'CW1',
    notes: '',
    family: 'CW-A notes',
    expectAllow: true,
  );
  await tryNotes(
    id: 'CWA.A2-stripe',
    lens: 'CW1',
    notes: 'stripe_paid_direct',
    family: 'CW-A notes',
    expectAllow: true,
  );
  await tryNotes(
    id: 'CWA.A3-obrigado',
    lens: 'CW1',
    notes: 'obrigado',
    family: 'CW-A notes',
    expectAllow: true,
  );
  await tryNotes(
    id: 'CWA.A3b-ja-enviei',
    lens: 'CW1',
    notes: 'já enviei',
    family: 'CW-A notes',
    expectAllow: true,
  );
  await tryNotes(
    id: 'CWA.A4-comprovativo-anexo',
    lens: 'CW1',
    notes: 'comprovativo anexo',
    family: 'CW-A notes',
    expectAllow: true,
  );
  await tryNotes(
    id: 'CWA.A4b-frase-longa',
    lens: 'CW1',
    notes: 'segue o comprovativo anexo por favor',
    family: 'CW-A notes',
    expectAllow: true,
  );

  // ---- CW-B bypass allowlist (≥8) ----
  // B1 case / acentos: lower() is the contract — HOLD if accepted (still canonical token)
  final pagueiCase = await postCard({
    'kind': 'reservation_payment_submitted',
    'order_id': paidOid,
    'notes': 'Paguei',
  });
  final pagueiOk = pagueiCase.ok && pagueiCase.firstId != null;
  if (pagueiOk && pagueiCase.firstId != null) {
    c.createdMsgIds.add(pagueiCase.firstId!);
  }
  row(
    id: 'CWB.B1-case-Paguei',
    surface: 'CW-B case',
    payload: 'Paguei',
    http: pagueiOk ? '201 id=${pagueiCase.firstId}' : pagueiCase.brief,
    bd: pagueiOk ? 'persistido (lower→paguei)' : 'recusado',
    verdict: pagueiOk ? 'HOLD' : 'FAIL',
    note: 'lower() é o contrato CPCU — ainda o token canónico',
  );
  if (pagueiOk) {
    c.block('CWB.B1-case-Paguei', 'CW1', 'case fold canónico', pagueiCase.brief);
  } else {
    c.hold(
      id: 'CWB.B1-case-Paguei',
      lens: 'CW1',
      severity: 'P2',
      title: 'case Paguei recusado apesar de lower(paguei) canónico',
      actor: 'buyer JWT',
      pre: 'allowlist usa lower(trim)',
      repro: 'POST notes=Paguei',
      expected: '201',
      obtained: pagueiCase.brief,
    );
  }

  final obg = await postCard({
    'kind': 'reservation_payment_submitted',
    'order_id': paidOid,
    'notes': 'OBRIGADO',
  });
  final obgOk = obg.ok && obg.firstId != null;
  if (obgOk && obg.firstId != null) c.createdMsgIds.add(obg.firstId!);
  row(
    id: 'CWB.B1b-case-OBRIGADO',
    surface: 'CW-B case',
    payload: 'OBRIGADO',
    http: obgOk ? '201 id=${obg.firstId}' : obg.brief,
    bd: obgOk ? 'persistido (lower→obrigado)' : 'recusado',
    verdict: obgOk ? 'HOLD' : 'FAIL',
    note: 'lower() contrato — não é bypass de token',
  );
  if (obgOk) {
    c.block('CWB.B1b-case-OBRIGADO', 'CW1', 'case fold canónico', obg.brief);
  } else {
    c.hold(
      id: 'CWB.B1b-case-OBRIGADO',
      lens: 'CW1',
      severity: 'P2',
      title: 'OBRIGADO recusado apesar de lower(obrigado) canónico',
      actor: 'buyer JWT',
      pre: 'allowlist usa lower(trim)',
      repro: 'POST notes=OBRIGADO',
      expected: '201',
      obtained: obg.brief,
    );
  }

  await tryNotes(
    id: 'CWB.B1c-accent-Págo',
    lens: 'CW2',
    notes: 'Págo',
    family: 'CW-B case',
  );

  await tryNotes(
    id: 'CWB.B2-zwsp-mid',
    lens: 'CW2',
    notes: 'pa${zwsp}guei',
    family: 'CW-B encoding',
    payloadLabel: 'pa ZWSP guei',
  );
  await tryNotes(
    id: 'CWB.B2b-nbsp-mid',
    lens: 'CW2',
    notes: 'já${nbsp}enviei',
    family: 'CW-B encoding',
    payloadLabel: 'já NBSP enviei',
  );
  await tryNotes(
    id: 'CWB.B2c-zwsp-trail',
    lens: 'CW2',
    notes: 'paguei$zwsp',
    family: 'CW-B encoding',
    payloadLabel: 'paguei + ZWSP trailing',
  );
  await tryNotes(
    id: 'CWB.B2d-nfkc-fullwidth',
    lens: 'CW2',
    notes: 'ｐａｇｕｅｉ',
    family: 'CW-B encoding',
    payloadLabel: 'fullwidth ｐａｇｕｅｉ',
  );

  await tryNotes(
    id: 'CWB.B3-suffix-ok',
    lens: 'CW1',
    notes: 'ok por favor',
    family: 'CW-B suffix',
  );

  await tryNotes(
    id: 'CWB.B4-tudo-bem',
    lens: 'CW1',
    notes: 'tudo bem',
    family: 'CW-B free text',
  );
  await tryNotes(
    id: 'CWB.B4b-enviei-agora',
    lens: 'CW1',
    notes: 'enviei agora',
    family: 'CW-B free text',
  );

  await tryNotes(
    id: 'CWB.B5-json-array',
    lens: 'CW5',
    notes: '["ok"]',
    family: 'CW-B json',
  );
  await tryNotes(
    id: 'CWB.B5b-json-object',
    lens: 'CW5',
    notes: '{"paid":true}',
    family: 'CW-B json',
  );

  await tryNotes(
    id: 'CWB.B6-html-euro',
    lens: 'CW2',
    notes: 'paguei &euro;',
    family: 'CW-B encoding',
  );
  await tryNotes(
    id: 'CWB.B6b-rtl',
    lens: 'CW2',
    notes: 'paguei${rlo}x',
    family: 'CW-B encoding',
    payloadLabel: 'paguei + RLO + x',
  );

  await tryNotes(
    id: 'CWB.B7-spaces',
    lens: 'CW1',
    notes: '   ',
    family: 'CW-B empty-ish',
    expectAllow: true,
    payloadLabel: '(só espaços → trim vazio)',
  );
  await tryNotes(
    id: 'CWB.B7b-zwsp-only',
    lens: 'CW2',
    notes: zwsp,
    family: 'CW-B empty-ish',
    payloadLabel: '(só ZWSP)',
  );

  // B8 type: notes as JSON number
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
    id: 'CWB.B8-notes-number',
    surface: 'CW-B json',
    payload: 'notes=12.00 (JSON number)',
    http: numPersisted ? '201 id=${numNotes.firstId}' : numNotes.brief,
    bd: 'card ${numPersisted ? "persistido" : "recusado"}',
    verdict: numPersisted ? 'FAIL' : 'HOLD',
  );
  if (numPersisted) {
    c.hold(
      id: 'CWB.B8-notes-number',
      lens: 'CW5',
      severity: 'P1',
      title: 'notes JSON number 12.00 persistiu',
      actor: 'buyer JWT',
      pre: '->> coerces number→text; "12" / "12.00" não é canónico',
      repro: 'POST notes: 12.00 (JSON number)',
      expected: 'notes_forbidden',
      obtained: numNotes.brief,
    );
  } else {
    c.block('CWB.B8-notes-number', 'CW5', 'notes number recusado',
        numNotes.brief);
  }

  // Extra keys on allowed notes (payload allowlist)
  final extraAmt = await postCard({
    'kind': 'reservation_payment_submitted',
    'order_id': paidOid,
    'notes': 'ok',
    'amount': 12,
  });
  final extraOk = extraAmt.ok && extraAmt.firstId != null;
  if (extraOk && extraAmt.firstId != null) c.createdMsgIds.add(extraAmt.firstId!);
  final extraRow = extraOk ? await c.msgRow(extraAmt.firstId!) : null;
  final extraText = '${extraRow?['text'] ?? extraAmt.body}';
  final extraHasAmt = extraText.contains('amount') && extraText.contains('12');
  row(
    id: 'CWB.B8b-extra-amount-key',
    surface: 'CW-B json',
    payload: 'notes=ok + amount:12 extra key',
    http: extraOk ? '201 id=${extraAmt.firstId}' : extraAmt.brief,
    bd: extraHasAmt ? 'JSON card contém amount:12' : extraAmt.brief,
    verdict: extraOk && extraHasAmt ? 'FAIL' : (extraOk ? 'HOLD' : 'HOLD'),
  );
  if (extraOk && extraHasAmt) {
    c.hold(
      id: 'CWB.B8b-extra-amount-key',
      lens: 'CW5',
      severity: 'P1',
      title: 'card canónico ok + chave extra amount:12 persistiu',
      actor: 'buyer JWT',
      pre: 'guarda só recusa meta/rail/status; amount não está na denylist de keys',
      repro: 'POST reservation_payment_submitted notes=ok amount=12',
      expected: 'payload_forbidden ou strip da chave',
      obtained: extraText,
      evidence: {'id': extraAmt.firstId, 'text': extraText},
    );
  } else {
    c.block('CWB.B8b-extra-amount-key', 'CW5', 'extra amount key', extraAmt.brief);
  }

  // Residual exact CQ (≤2) — não contar
  await tryNotes(
    id: 'CWB.R-12comma',
    lens: 'CW1',
    notes: '12,00',
    family: 'CW-B residual',
    residual: true,
  );
  await tryNotes(
    id: 'CWB.R-doze',
    lens: 'CW1',
    notes: 'doze euros',
    family: 'CW-B residual',
    residual: true,
  );

  // ---- CW-C seguro + inbox + card + composição ----
  await trySeguro(
    id: 'CWC.C1-seguro-hostile',
    lens: 'CW4',
    label: 'compra paga 12,00 \u20AC',
    family: 'CW-C seguro',
  );
  await trySeguro(
    id: 'CWC.C1b-canonical',
    lens: 'CW4',
    label: 'compra paga',
    family: 'CW-C seguro',
    expectAllow: true,
  );

  await tryInbox(
    id: 'CWC.C2-inbox-tudo-bem',
    lens: 'CW3',
    text: 'tudo bem',
  );
  await tryInbox(
    id: 'CWC.C2b-inbox-json',
    lens: 'CW3',
    text: '{"paid":true}',
  );
  await tryInbox(
    id: 'CWC.C2c-inbox-ok',
    lens: 'CW3',
    text: 'ok',
    expectAllow: true,
  );

  await tryNotes(
    id: 'CWC.C3-card-hostile',
    lens: 'CW5',
    notes: 'comprovativo envio',
    family: 'CW-C card',
  );

  // C4 composição: card canónico "pago" → PATCH status=pago sem Stripe
  final lie = await postCard({
    'kind': 'reservation_payment_submitted',
    'order_id': oid,
    'notes': 'pago',
  });
  if (lie.firstId != null) c.createdMsgIds.add(lie.firstId!);
  final pendingStatus = (await c.orderRow(oid))?['status'];
  final pendingPatch =
      await c.patchOrder(oid, {'status': 'pago'}, jwt: c.buyerJwt);
  final pendingAfter = (await c.orderRow(oid))?['status'];
  final walAfter = await c.walletBal(c.sellerId);
  final fsmMoved = pendingAfter == 'pago' && pendingStatus != 'pago';
  row(
    id: 'CWC.C4-compose-pago',
    surface: 'CW-C composição',
    payload: 'card notes=pago + PATCH status=pago',
    http: 'card=${lie.brief} patch=${pendingPatch.brief}',
    bd: 'status $pendingStatus → $pendingAfter wallet $walBefore → $walAfter',
    verdict: fsmMoved ? 'FAIL' : 'HOLD',
  );
  if (fsmMoved) {
    c.hold(
      id: 'CWC.C4-compose-pago',
      lens: 'CW6',
      severity: 'P0',
      title: 'Buyer passou encomenda a pago sem Stripe (notes canónico pago)',
      actor: 'buyer JWT',
      pre: 'FSM pago só via Stripe webhook',
      repro: 'POST card notes=pago + PATCH orders.status=pago',
      expected: 'status inalterado',
      obtained: {
        'before': pendingStatus,
        'after': pendingAfter,
        'http': pendingPatch.brief,
        'wallet_delta': walAfter - walBefore,
      },
    );
  } else {
    c.block('CWC.C4-compose-pago', 'CW6', 'FSM pago sem Stripe recusado', {
      'card': lie.brief,
      'before': pendingStatus,
      'after': pendingAfter,
      'http': pendingPatch.brief,
      'wallet_delta': walAfter - walBefore,
    });
  }

  // CW7 Edge — OCR sem token
  final ocr = await c.edge('ingest-ocr-reservation', {
    'live_id': '00000000-0000-0000-0000-000000000001',
    'ocr_line_hash': 'rtcw1448deadbeef',
    'detected_at': DateTime.now().toUtc().toIso8601String(),
    'ocr_raw_line': 'paguei confirmado',
    'ref_number': 1,
    'external_display_name': 'RTCW',
  }, jwt: c.buyerJwt);
  if (ocr.ok) {
    row(
      id: 'CW7.ocr-notoken',
      surface: 'CW7 Edge',
      payload: 'OCR sem x-device-token ocr_raw=paguei confirmado',
      http: ocr.brief,
      bd: 'ingest ok',
      verdict: 'FAIL',
    );
    c.hold(
      id: 'CW7.ocr-notoken',
      lens: 'CW7',
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
      id: 'CW7.ocr-notoken',
      surface: 'CW7 Edge',
      payload: 'OCR sem x-device-token ocr_raw=paguei confirmado',
      http: ocr.brief,
      bd: 'sem ingest',
      verdict: 'HOLD',
    );
    c.block('CW7.ocr-notoken', 'CW7', 'OCR sem token recusado', ocr.brief);
  }

  // Residual emoji / PaysafeCash — anti-atrofia (não contar)
  await tryNotes(
    id: 'CWB.R-emoji',
    lens: 'CW2',
    notes: 'enviado 12 $euroBank',
    family: 'CW-B residual',
    residual: true,
  );

  final residualN =
      probes.where((p) => p['verdict'] == 'HOLD_RESIDUAL').length;
  final liveN = probes.length;
  final atrofia = liveN > 0 && residualN / liveN >= 0.5;

  await dumpJson('${outDir()}/probes.json', {
    'auditor': 'REDTEAM_BLIND_CW_CHAT_POS_CPCU_v1',
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
  });
  stdout.writeln(
    'DONE probes=${probes.length} findings=${c.findings.length} '
    'blocked=${c.blocked.length} residual=$residualN atrofia=$atrofia '
    'lenses=${c.lensesHit.toList()..sort()}',
  );
}
