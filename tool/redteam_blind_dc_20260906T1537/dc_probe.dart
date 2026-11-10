/// REDTEAM_BLIND_DC_CHAT_POS_CVDA_v1 — bypass residual fino pós-CW.
/// Staging only. NÃO CORRIGIR. Residual 12,00 / doze euros ≤2 se HOLD — não contar.
import 'dart:convert';
import 'dart:io';

import '_rtdc.dart';

Future<void> main() async {
  final c = Rtdc.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  final sku = await c.createProduct(title: '$prefix-dca', price: 12);
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
          pre: 'vazio / stripe_paid_direct / obrigado / já enviei',
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
        pre: 'só tokens canónicos exactos após lower(trim); resto deny',
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
    String? payloadLabel,
  }) async {
    final h = await postCard({
      'kind': 'seguro_fleaber_paid',
      'order_id': paidOid,
      'label': label,
    });
    final persisted = h.ok && h.firstId != null;
    if (persisted && h.firstId != null) c.createdMsgIds.add(h.firstId!);
    final status = '${(await c.orderRow(paidOid))?['status']}';
    final shown = payloadLabel ?? (label.isEmpty ? '(label vazio)' : label);
    if (expectAllow) {
      if (persisted) {
        row(
          id: id,
          surface: family,
          payload: shown,
          http: '201 id=${h.firstId}',
          bd: 'orders.status=$status',
          verdict: 'PASS',
        );
        c.block(id, lens, 'label allowlist aceitou', h.brief);
      } else {
        row(
          id: id,
          surface: family,
          payload: shown,
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
        payload: shown,
        http: '201 id=${h.firstId}',
        bd: 'orders.status=$status · label persistido',
        verdict: 'FAIL',
      );
      c.hold(
        id: id,
        lens: lens,
        severity: 'P1',
        title: 'seguro label fora da allowlist: $shown',
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
        payload: shown,
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
        surface: 'DC-B inbox',
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
          surface: 'DC-B inbox',
          payload: shown,
          http: '${h.status}',
          bd: 'chats.last_message stored exact',
          verdict: 'PASS',
        );
        c.block(id, lens, 'inbox canónico aceite', stored);
      } else {
        row(
          id: id,
          surface: 'DC-B inbox',
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
        surface: 'DC-B inbox',
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
        surface: 'DC-B inbox',
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
  const wj = '\u2060';
  const shy = '\u00AD';
  const zwnj = '\u200C';
  const rlo = '\u202E';
  const fsi = '\u2068';
  const tagA = '\uE0061'; // TAG LATIN SMALL LETTER A
  const cyrA = '\u0430'; // Cyrillic а
  const nfdJa = 'ja\u0301 enviei'; // NFD já enviei
  const smallPaguei = '\u1D18\u1D00\u0262\u1D1C\u1D07\u026A'; // ᴘᴀɢᴜᴇɪ-ish
  final tagsPaguei =
      '${tagA}paguei'; // canonical + TAG (invisible) — not exact
  final tagsOnly = '$tagA$tagA$tagA';

  // ---- DC-A positivos (≥3) ----
  await tryNotes(
    id: 'DCA.A1-empty',
    lens: 'DC1',
    notes: '',
    family: 'DC-A notes',
    expectAllow: true,
  );
  await tryNotes(
    id: 'DCA.A2-stripe',
    lens: 'DC1',
    notes: 'stripe_paid_direct',
    family: 'DC-A notes',
    expectAllow: true,
  );
  await tryNotes(
    id: 'DCA.A3-obrigado',
    lens: 'DC1',
    notes: 'obrigado',
    family: 'DC-A notes',
    expectAllow: true,
  );
  await tryNotes(
    id: 'DCA.A3b-ja-enviei',
    lens: 'DC1',
    notes: 'já enviei',
    family: 'DC-A notes',
    expectAllow: true,
  );

  // ---- DC-B bypass (≥7) residual fino vs CW ----
  // B1 canonical + ZWSP/NBSP/WJ/SHY (não o U+200B mid exacto CW)
  await tryNotes(
    id: 'DCB.B1-zwsp-prefix',
    lens: 'DC2',
    notes: '${zwsp}paguei',
    family: 'DC-B encoding',
    payloadLabel: 'ZWSP + paguei',
  );
  await tryNotes(
    id: 'DCB.B1-wj-mid',
    lens: 'DC2',
    notes: 'pa${wj}guei',
    family: 'DC-B encoding',
    payloadLabel: 'pa WJ guei',
  );
  await tryNotes(
    id: 'DCB.B1b-shy-mid',
    lens: 'DC2',
    notes: 'pa${shy}guei',
    family: 'DC-B encoding',
    payloadLabel: 'pa SHY guei',
  );
  await tryNotes(
    id: 'DCB.B1c-nbsp-ok',
    lens: 'DC2',
    notes: 'o${nbsp}k',
    family: 'DC-B encoding',
    payloadLabel: 'o NBSP k',
  );
  await tryNotes(
    id: 'DCB.B1d-zwnj',
    lens: 'DC2',
    notes: 'pa${zwnj}guei',
    family: 'DC-B encoding',
    payloadLabel: 'pa ZWNJ guei',
  );

  // B2 case / acento / homoglyph em canónico
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
    id: 'DCB.B2-case-Paguei',
    surface: 'DC-B case',
    payload: 'Paguei',
    http: pagueiOk ? '201 id=${pagueiCase.firstId}' : pagueiCase.brief,
    bd: pagueiOk ? 'persistido (lower→paguei)' : 'recusado',
    verdict: pagueiOk ? 'HOLD' : 'FAIL',
    note: 'lower() é o contrato — ainda o token canónico',
  );
  if (pagueiOk) {
    c.block('DCB.B2-case-Paguei', 'DC1', 'case fold canónico', pagueiCase.brief);
  } else {
    c.hold(
      id: 'DCB.B2-case-Paguei',
      lens: 'DC1',
      severity: 'P2',
      title: 'case Paguei recusado apesar de lower(paguei) canónico',
      actor: 'buyer JWT',
      pre: 'allowlist usa lower(trim)',
      repro: 'POST notes=Paguei',
      expected: '201',
      obtained: pagueiCase.brief,
    );
  }

  await tryNotes(
    id: 'DCB.B2b-homoglyph-cyrA',
    lens: 'DC2',
    notes: 'p${cyrA}guei',
    family: 'DC-B homoglyph',
    payloadLabel: 'p + Cyrillic а + guei',
  );
  await tryNotes(
    id: 'DCB.B2c-nfd-ja',
    lens: 'DC2',
    notes: nfdJa,
    family: 'DC-B homoglyph',
    payloadLabel: 'já enviei NFD (a + U+0301)',
  );
  await tryNotes(
    id: 'DCB.B2d-smallcaps',
    lens: 'DC2',
    notes: smallPaguei,
    family: 'DC-B homoglyph',
    payloadLabel: 'small-caps paguei',
  );

  // B3 suffix
  await tryNotes(
    id: 'DCB.B3-suffix-ok',
    lens: 'DC1',
    notes: 'ok por favor',
    family: 'DC-B suffix',
  );

  // B4 texto livre
  await tryNotes(
    id: 'DCB.B4-tudo-bem',
    lens: 'DC1',
    notes: 'tudo bem',
    family: 'DC-B free text',
  );

  // B5 JSON / type coercion (não o 12.00 number exacto CW)
  final boolNotes = await postCard({
    'kind': 'reservation_payment_submitted',
    'order_id': paidOid,
    'notes': true,
  });
  final boolPersisted = boolNotes.ok && boolNotes.firstId != null;
  if (boolPersisted && boolNotes.firstId != null) {
    c.createdMsgIds.add(boolNotes.firstId!);
  }
  row(
    id: 'DCB.B5-notes-bool',
    surface: 'DC-B json',
    payload: 'notes=true (JSON boolean)',
    http: boolPersisted ? '201 id=${boolNotes.firstId}' : boolNotes.brief,
    bd: 'card ${boolPersisted ? "persistido" : "recusado"}',
    verdict: boolPersisted ? 'FAIL' : 'HOLD',
  );
  if (boolPersisted) {
    c.hold(
      id: 'DCB.B5-notes-bool',
      lens: 'DC5',
      severity: 'P1',
      title: 'notes JSON boolean true persistiu',
      actor: 'buyer JWT',
      pre: '->> coerces bool→text; "true" não é canónico',
      repro: 'POST notes: true (JSON boolean)',
      expected: 'notes_forbidden',
      obtained: boolNotes.brief,
    );
  } else {
    c.block('DCB.B5-notes-bool', 'DC5', 'notes boolean recusado',
        boolNotes.brief);
  }

  final arrNotes = await postCard({
    'kind': 'reservation_payment_submitted',
    'order_id': paidOid,
    'notes': <Object?>['ok'],
  });
  final arrPersisted = arrNotes.ok && arrNotes.firstId != null;
  if (arrPersisted && arrNotes.firstId != null) {
    c.createdMsgIds.add(arrNotes.firstId!);
  }
  row(
    id: 'DCB.B5b-notes-array',
    surface: 'DC-B json',
    payload: 'notes=["ok"] (JSON array type)',
    http: arrPersisted ? '201 id=${arrNotes.firstId}' : arrNotes.brief,
    bd: 'card ${arrPersisted ? "persistido" : "recusado"}',
    verdict: arrPersisted ? 'FAIL' : 'HOLD',
  );
  if (arrPersisted) {
    c.hold(
      id: 'DCB.B5b-notes-array',
      lens: 'DC5',
      severity: 'P1',
      title: 'notes JSON array ["ok"] persistiu',
      actor: 'buyer JWT',
      pre: 'array não é token canónico',
      repro: 'POST notes: ["ok"] (JSON array)',
      expected: 'notes_forbidden',
      obtained: arrNotes.brief,
    );
  } else {
    c.block('DCB.B5b-notes-array', 'DC5', 'notes array recusado', arrNotes.brief);
  }

  final nullNotes = await postCard({
    'kind': 'reservation_payment_submitted',
    'order_id': paidOid,
    'notes': null,
  });
  final nullPersisted = nullNotes.ok && nullNotes.firstId != null;
  if (nullPersisted && nullNotes.firstId != null) {
    c.createdMsgIds.add(nullNotes.firstId!);
  }
  row(
    id: 'DCB.B5c-notes-null',
    surface: 'DC-B json',
    payload: 'notes=null (JSON null → coalesce vazio)',
    http: nullPersisted ? '201 id=${nullNotes.firstId}' : nullNotes.brief,
    bd: 'card ${nullPersisted ? "persistido=vazio canónico" : "recusado"}',
    verdict: nullPersisted ? 'HOLD' : 'HOLD',
    note: 'null→vazio = A1; não é bypass de token',
  );
  c.block('DCB.B5c-notes-null', 'DC5', 'notes null coalesce', nullNotes.brief);

  // B6 RTL / tags / zero-width só
  await tryNotes(
    id: 'DCB.B6-rtl',
    lens: 'DC2',
    notes: '${rlo}paguei',
    family: 'DC-B encoding',
    payloadLabel: 'RLO + paguei',
  );
  await tryNotes(
    id: 'DCB.B6b-tags-wrap',
    lens: 'DC2',
    notes: tagsPaguei,
    family: 'DC-B encoding',
    payloadLabel: 'TAG-a + paguei',
  );
  await tryNotes(
    id: 'DCB.B6c-tags-only',
    lens: 'DC2',
    notes: tagsOnly,
    family: 'DC-B encoding',
    payloadLabel: '(só Unicode TAG U+E0061 ×3)',
  );
  await tryNotes(
    id: 'DCB.B6d-fsi',
    lens: 'DC2',
    notes: '${fsi}paguei',
    family: 'DC-B encoding',
    payloadLabel: 'FSI + paguei',
  );

  // B7 inbox PATCH hostil
  await tryInbox(
    id: 'DCB.B7-inbox-tudo-bem',
    lens: 'DC3',
    text: 'tudo bem',
  );
  await tryInbox(
    id: 'DCB.B7b-inbox-homoglyph',
    lens: 'DC3',
    text: 'p${cyrA}guei',
    payloadLabel: 'inbox p + Cyrillic а + guei',
  );
  await tryInbox(
    id: 'DCB.B7c-inbox-suffix',
    lens: 'DC3',
    text: 'ok por favor',
  );
  await tryInbox(
    id: 'DCB.B7d-inbox-tags',
    lens: 'DC3',
    text: tagsPaguei,
    payloadLabel: 'inbox TAG-a + paguei',
  );

  // Residual exacto (≤2) — não contar
  await tryNotes(
    id: 'DCB.R-12comma',
    lens: 'DC1',
    notes: '12,00',
    family: 'DC-B residual',
    residual: true,
  );
  await tryNotes(
    id: 'DCB.R-doze',
    lens: 'DC1',
    notes: 'doze euros',
    family: 'DC-B residual',
    residual: true,
  );

  // ---- DC-C seguro + card + FSM + storage ----
  await trySeguro(
    id: 'DCC.C1-seguro-hostile',
    lens: 'DC4',
    label: 'compra paga 12,00 \u20AC',
    family: 'DC-C seguro',
  );
  await trySeguro(
    id: 'DCC.C1b-canonical',
    lens: 'DC4',
    label: 'compra paga',
    family: 'DC-C seguro',
    expectAllow: true,
  );
  await trySeguro(
    id: 'DCC.C1c-homoglyph',
    lens: 'DC4',
    label: 'c${cyrA}mpra paga',
    family: 'DC-C seguro',
    payloadLabel: 'c + Cyrillic а + mpra paga',
  );

  await tryNotes(
    id: 'DCC.C2-card-hostile',
    lens: 'DC5',
    notes: 'comprovativo envio',
    family: 'DC-C card',
  );
  final railKey = await postCard({
    'kind': 'reservation_payment_submitted',
    'order_id': paidOid,
    'notes': 'ok',
    'rail': 'mbway',
  });
  final railOk = railKey.ok && railKey.firstId != null;
  if (railOk && railKey.firstId != null) c.createdMsgIds.add(railKey.firstId!);
  row(
    id: 'DCC.C2b-payload-rail',
    surface: 'DC-C card',
    payload: 'notes=ok + rail=mbway',
    http: railOk ? '201 id=${railKey.firstId}' : railKey.brief,
    bd: railOk ? 'payload extra persistido' : 'recusado',
    verdict: railOk ? 'FAIL' : 'HOLD',
  );
  if (railOk) {
    c.hold(
      id: 'DCC.C2b-payload-rail',
      lens: 'DC5',
      severity: 'P1',
      title: 'card canónico ok + chave rail=mbway persistiu',
      actor: 'buyer JWT',
      pre: 'meta/rail/status denylist',
      repro: 'POST reservation_payment_submitted notes=ok rail=mbway',
      expected: 'payload_forbidden',
      obtained: railKey.brief,
    );
  } else {
    c.block('DCC.C2b-payload-rail', 'DC5', 'rail key recusado', railKey.brief);
  }

  // malformed JSON — trigger exception when others → return NEW
  final malformed = await c.postMsg(
    chatId: chatId,
    text:
        'FLEABER_JSON_V1:{"kind":"reservation_payment_submitted","order_id":"$paidOid","notes":"paguei"',
  );
  final malOk = malformed.ok && malformed.firstId != null;
  if (malOk && malformed.firstId != null) {
    c.createdMsgIds.add(malformed.firstId!);
  }
  row(
    id: 'DCC.C2c-malformed-json',
    surface: 'DC-C card',
    payload: 'FLEABER_JSON_V1 card truncado (JSON inválido)',
    http: malOk ? '201 id=${malformed.firstId}' : malformed.brief,
    bd: malOk ? 'texto cru persistido' : 'recusado',
    verdict: malOk ? 'FAIL' : 'HOLD',
  );
  if (malOk) {
    c.hold(
      id: 'DCC.C2c-malformed-json',
      lens: 'DC5',
      severity: 'P2',
      title: 'JSON card truncado bypassa guarda (exception→return NEW)',
      actor: 'buyer JWT',
      pre: 'parse jsonb falha → trigger ignora o card',
      repro: 'POST FLEABER_JSON_V1:{…notes:"paguei"  (sem fechar)',
      expected: '4xx / notes_forbidden',
      obtained: malformed.brief,
      evidence: {'id': malformed.firstId},
    );
  } else {
    c.block('DCC.C2c-malformed-json', 'DC5', 'JSON inválido recusado',
        malformed.brief);
  }

  // C3 PATCH pago sem Stripe
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
    id: 'DCC.C3-compose-pago',
    surface: 'DC-C composição',
    payload: 'card notes=pago + PATCH status=pago',
    http: 'card=${lie.brief} patch=${pendingPatch.brief}',
    bd: 'status $pendingStatus → $pendingAfter wallet $walBefore → $walAfter',
    verdict: fsmMoved ? 'FAIL' : 'HOLD',
  );
  if (fsmMoved) {
    c.hold(
      id: 'DCC.C3-compose-pago',
      lens: 'DC6',
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
    c.block('DCC.C3-compose-pago', 'DC6', 'FSM pago sem Stripe recusado', {
      'card': lie.brief,
      'before': pendingStatus,
      'after': pendingAfter,
      'http': pendingPatch.brief,
      'wallet_delta': walAfter - walBefore,
    });
  }

  // C4 storage alheio
  final upAlien = await c.storageUpload(
    objectName:
        'order_proofs/${c.buyer2Id}/00000000-0000-0000-0000-000000000099/x.png',
    bytes: png1x1,
    jwt: c.buyerJwt,
  );
  if (upAlien.ok) {
    row(
      id: 'DCC.C4-upload-alien',
      surface: 'DC-C storage',
      payload: 'B1 UPLOAD path B2',
      http: upAlien.brief,
      bd: 'object criado',
      verdict: 'FAIL',
    );
    c.hold(
      id: 'DCC.C4-upload-alien',
      lens: 'DC5',
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
      id: 'DCC.C4-upload-alien',
      surface: 'DC-C storage',
      payload: 'B1 UPLOAD path B2',
      http: upAlien.brief,
      bd: 'sem objecto',
      verdict: 'HOLD',
    );
    c.block('DCC.C4-upload-alien', 'DC5', 'upload path B2 recusado',
        upAlien.brief);
  }

  // proof_url apontando para prefixo B2 (mesmo que upload falhe)
  final alienUrl =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/order_proofs/${c.buyer2Id}/00000000-0000-0000-0000-000000000099/x.png';
  final proofAlien = await postCard({
    'kind': 'reservation_payment_submitted',
    'order_id': paidOid,
    'notes': 'ok',
    'proof_url': alienUrl,
  });
  final proofOk = proofAlien.ok && proofAlien.firstId != null;
  if (proofOk && proofAlien.firstId != null) {
    c.createdMsgIds.add(proofAlien.firstId!);
  }
  row(
    id: 'DCC.C4b-proof-alien',
    surface: 'DC-C storage',
    payload: 'card notes=ok proof_url path B2',
    http: proofOk ? '201 id=${proofAlien.firstId}' : proofAlien.brief,
    bd: proofOk ? 'URL alheia no card' : 'recusado',
    verdict: proofOk ? 'FAIL' : 'HOLD',
  );
  if (proofOk) {
    c.hold(
      id: 'DCC.C4b-proof-alien',
      lens: 'DC5',
      severity: 'P1',
      title: 'card com proof_url no path de B2',
      actor: 'buyer JWT',
      pre: 'prefixo order_proofs/{buyer_da_encomenda}/{oid}/',
      repro: 'POST proof_url=…/order_proofs/{b2}/…',
      expected: 'url_denied',
      obtained: proofAlien.brief,
    );
  } else {
    c.block('DCC.C4b-proof-alien', 'DC5', 'proof_url B2 recusado',
        proofAlien.brief);
  }

  // DC7 Edge OCR
  final ocr = await c.edge('ingest-ocr-reservation', {
    'live_id': '00000000-0000-0000-0000-000000000001',
    'ocr_line_hash': 'rtdc1537deadbeef',
    'detected_at': DateTime.now().toUtc().toIso8601String(),
    'ocr_raw_line': 'paguei confirmado',
    'ref_number': 1,
    'external_display_name': 'RTDC',
  }, jwt: c.buyerJwt);
  if (ocr.ok) {
    row(
      id: 'DC7.ocr-notoken',
      surface: 'DC7 Edge',
      payload: 'OCR sem x-device-token ocr_raw=paguei confirmado',
      http: ocr.brief,
      bd: 'ingest ok',
      verdict: 'FAIL',
    );
    c.hold(
      id: 'DC7.ocr-notoken',
      lens: 'DC7',
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
      id: 'DC7.ocr-notoken',
      surface: 'DC7 Edge',
      payload: 'OCR sem x-device-token ocr_raw=paguei confirmado',
      http: ocr.brief,
      bd: 'sem ingest',
      verdict: 'HOLD',
    );
    c.block('DC7.ocr-notoken', 'DC7', 'OCR sem token recusado', ocr.brief);
  }

  final residualN =
      probes.where((p) => p['verdict'] == 'HOLD_RESIDUAL').length;
  final liveN = probes.length;
  final atrofia = liveN > 0 && residualN / liveN >= 0.5;

  await dumpJson('${outDir()}/probes.json', {
    'auditor': 'REDTEAM_BLIND_DC_CHAT_POS_CVDA_v1',
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
