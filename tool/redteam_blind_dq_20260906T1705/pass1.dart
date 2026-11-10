/// RED TEAM CEGO DQ — envio / disputa / storage / label. Staging only. Não corrige.
/// Matriz A≥5 B≥4 C≥3 D≥2 · ≥3 classe_nova · lentes DQ1–DQ7 · quota ≥14.
import 'dart:io';
import '_rtdq.dart';

const pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

const jsBytes = <int>[
  0x61, 0x6C, 0x65, 0x72, 0x74, 0x28, 0x31, 0x29, 0x3B, // alert(1);
];

bool isDenied(HttpHit h) {
  final raw = h.body.toLowerCase();
  return h.status == 400 ||
      h.status == 401 ||
      h.status == 403 ||
      h.status == 404 ||
      h.status == 409 ||
      h.status == 415 ||
      h.status == 422 ||
      raw.contains('42501') ||
      raw.contains('23514') ||
      raw.contains('denied') ||
      raw.contains('forbidden') ||
      raw.contains('sem permiss') ||
      raw.contains('already_exists') ||
      raw.contains('nosuchkey') ||
      raw.contains('invalidkey');
}

bool emptyOk(HttpHit h) {
  if (h.status == 204) return true;
  if (!h.ok) return false;
  if (h.list.isEmpty && h.map == null && (h.body.isEmpty || h.body == '[]')) {
    return true;
  }
  return false;
}

bool rpcFalse(HttpHit h) {
  return h.body.trim() == 'false' || h.json == false;
}

bool rpcTrue(HttpHit h) {
  return h.body.trim() == 'true' || h.json == true;
}

void main() async {
  final c = Rtdq.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  c.well('DQ-A');
  c.well('DQ-B');
  c.well('DQ-C');
  c.well('DQ-D');

  Future<({String oid, String pid, String? pi})> mustPay(String lens,
      {int qty = 1}) async {
    final paid = await c.payToPago(lens: lens, initialQty: qty);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  Future<HttpHit> canonRpc(String url) {
    return c.rpc('batata_storage_url_path_canonical', {'p_url': url},
        service: true);
  }

  Future<HttpHit> proofOkRpc(String url, String buyer, String oid) {
    return c.rpc(
      'batata_dispute_proof_url_ok',
      {'p_url': url, 'p_buyer': buyer, 'p_oid': oid},
      service: true,
    );
  }

  void denyOrHold({
    required String id,
    required String matrix,
    required String lens,
    required String payload,
    required HttpHit hit,
    String? bd,
    required String expectedDeny,
    bool classeNova = false,
    bool residual = false,
    String severity = 'P2',
    String? title,
    bool persistedOverride = false,
  }) {
    final persisted = persistedOverride || (hit.ok && !isDenied(hit) && !emptyOk(hit));
    if (residual) {
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: hit.brief,
        bd: bd,
        result: persisted ? 'RESIDUAL' : 'FAIL',
        classeNova: classeNova,
      );
      if (!persisted) {
        c.block(id, lens, title ?? id, hit);
      } else {
        c.note(id, 'residual anti-atrofia — NÃO CONTAR', hit, lens: lens);
      }
      return;
    }
    if (persisted) {
      c.hold(
        id: id,
        lens: lens,
        severity: severity,
        title: title ?? id,
        actor: 'buyer JWT',
        pre: payload,
        repro: id,
        expected: expectedDeny,
        obtained: hit.brief,
      );
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: hit.brief,
        bd: bd,
        result: 'HOLD',
        classeNova: classeNova,
      );
    } else {
      c.block(id, lens, title ?? id, hit);
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: hit.brief,
        bd: bd,
        result: 'FAIL',
        classeNova: classeNova,
      );
    }
  }

  void passHappy({
    required String id,
    required String matrix,
    required String lens,
    required String payload,
    required HttpHit hit,
    String? bd,
    required bool ok,
    String severity = 'P2',
    String? title,
    bool classeNova = false,
  }) {
    if (ok) {
      c.block(id, lens, title ?? id, hit);
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: hit.brief,
        bd: bd,
        result: 'FAIL',
        classeNova: classeNova,
      );
    } else {
      c.hold(
        id: id,
        lens: lens,
        severity: severity,
        title: title ?? id,
        actor: 'buyer/seller JWT',
        pre: payload,
        repro: id,
        expected: 'happy path 2xx',
        obtained: hit.brief,
      );
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: hit.brief,
        bd: bd,
        result: 'HOLD',
        classeNova: classeNova,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Fixtures Stripe TEST
  // ---------------------------------------------------------------------------
  final hp = await mustPay('DQ6', qty: 1);
  if (!await c.toEnviado(hp.oid)) throw StateError('enviado hp');
  if (!await c.toConcluido(hp.oid)) throw StateError('concluido hp');

  final minePath = c.disputeObj(c.buyerId!, hp.oid, 'ok.png');
  final up = await c.storageUpload(
    objectName: minePath,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final signed = await c.signObject(minePath, jwt: c.buyerJwt);
  c.note('DQ6.upload', 'PNG próprio assinado', {
    'up': up.brief,
    'signed': signed,
    'path': minePath,
  }, lens: 'DQ6');

  final alienKey =
      'order_disputes/${c.buyer2Id}/00000000-0000-0000-0000-00000000dq02/rtdq-secret.png';
  final alienUp = await c.storageUpload(
    objectName: alienKey,
    bytes: pngBytes,
    jwt: c.buyer2Jwt,
  );
  c.note('DQ6.alien', 'objecto B2', alienUp.brief, lens: 'DQ6');

  String ownSign(String file) =>
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/${c.buyerId}/${hp.oid}/$file';

  final signedOrOwn = signed ?? ownSign('ok.png');

  // ===========================================================================
  // DQ-A Storage / proof (≥5)
  // ===========================================================================

  // A1 path ../ / encoded dots
  final a1Name =
      'order_disputes/${c.buyerId}/../${c.buyer2Id}/rtdq-dotdot.png';
  final a1Up = await c.storageUpload(
    objectName: a1Name,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final a1GetAlien = await c.storageGet(
    'order_disputes/${c.buyer2Id}/rtdq-dotdot.png',
    jwt: c.buyerJwt,
  );
  final a1GetCanon = await c.storageGet(a1Name, jwt: c.buyerJwt);
  final a1Loot = a1Up.ok &&
      !isDenied(a1GetAlien) &&
      (a1GetAlien.body.contains('PNG') || a1GetAlien.status == 200);
  c.note('A1.dotdot', 'upload ../', {
    'up': a1Up.brief,
    'getAlien': a1GetAlien.brief,
    'getCanon': a1GetCanon.brief,
  }, lens: 'DQ1');
  denyOrHold(
    id: 'DQ-A1.path_dotdot_upload',
    matrix: 'DQ-A',
    lens: 'DQ1',
    payload: 'POST object order_disputes/{B1}/../{B2}/rtdq-dotdot.png',
    hit: a1Loot ? a1GetAlien : a1Up,
    bd: 'up=${a1Up.status} getAlien=${a1GetAlien.status} loot=$a1Loot',
    expectedDeny: '403 RLS / sem GET no prefixo B2',
    persistedOverride: a1Loot,
    title: 'traversal ../ no storage',
  );

  final a1bUrl = '$signedOrOwn%2e%2e%2f${c.buyer2Id}/rtdq-secret.png';
  final a1bOk = await proofOkRpc(a1bUrl, c.buyerId!, hp.oid);
  denyOrHold(
    id: 'DQ-A1b.encoded_dots_url',
    matrix: 'DQ-A',
    lens: 'DQ1',
    payload: 'RPC proof_ok signed + %2e%2e%2f + path B2',
    hit: a1bOk,
    bd: 'rpc=${a1bOk.body}',
    expectedDeny: 'false / denied',
    persistedOverride: rpcTrue(a1bOk),
    title: 'encoded dots na proof URL',
  );

  // A2 URL outro buyer / outra order
  final a2Signed = await c.signObject(alienKey, jwt: c.buyer2Jwt);
  final a2Url = a2Signed ??
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$alienKey';
  final a2Ok = await proofOkRpc(a2Url, c.buyerId!, hp.oid);
  final a2Get = await c.storageGet(alienKey, jwt: c.buyerJwt);
  denyOrHold(
    id: 'DQ-A2.proof_url_other_buyer',
    matrix: 'DQ-A',
    lens: 'DQ2',
    payload: 'RPC proof_ok URL signed B2 em disputa B1 + GET objecto B2 como B1',
    hit: a2Ok,
    bd: 'rpc=${a2Ok.body} getB2asB1=${a2Get.brief}',
    expectedDeny: 'rpc false + GET NoSuchKey/403',
    persistedOverride: rpcTrue(a2Ok) || (a2Get.ok && !isDenied(a2Get)),
    title: 'URL prova outro buyer',
  );

  // A3 content-type / extension mismatch — classe_nova
  final a3Path = c.disputeObj(c.buyerId!, hp.oid, 'evil.js');
  final a3Up = await c.storageUpload(
    objectName: a3Path,
    bytes: jsBytes,
    jwt: c.buyerJwt,
    contentType: 'application/javascript',
  );
  final a3Sign = await c.signObject(a3Path, jwt: c.buyerJwt);
  final a3Url = a3Sign ?? ownSign('evil.js');
  final a3Ok = await proofOkRpc(a3Url, c.buyerId!, hp.oid);
  final a3Accept = a3Up.ok && rpcTrue(a3Ok);
  c.note('A3.ct', 'JS como proof', {
    'up': a3Up.brief,
    'rpc': a3Ok.body,
    'signed': a3Sign,
  }, lens: 'DQ6');
  // Hygiene: upload JS may be allowed by storage; proof helper must still
  // accept only path shape. HOLD only if helper true AND we can persist on disputa.
  denyOrHold(
    id: 'DQ-A3.ct_mismatch_js',
    matrix: 'DQ-A',
    lens: 'DQ6',
    payload: 'upload evil.js CT=application/javascript + proof_ok',
    hit: a3Ok,
    bd: 'up=${a3Up.status} rpc=${a3Ok.body} accept=$a3Accept',
    expectedDeny: 'upload 4xx ou proof_ok false (não imagem)',
    classeNova: true,
    persistedOverride: a3Accept,
    title: 'content-type JS aceite como prova',
    severity: 'P2',
  );

  // A4 signed URL reuse após revoke — classe_nova
  final a4Path = c.disputeObj(c.buyerId!, hp.oid, 'revoke.png');
  final a4Up = await c.storageUpload(
    objectName: a4Path,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final a4Signed = await c.signObject(a4Path, jwt: c.buyerJwt);
  HttpHit a4GetBefore = HttpHit(0, 'no_sign', null);
  HttpHit a4Del = HttpHit(0, 'no_sign', null);
  HttpHit a4GetAfter = HttpHit(0, 'no_sign', null);
  if (a4Signed != null) {
    a4GetBefore = await c.storageGetSigned(a4Signed);
    a4Del = await c.storageDelete(a4Path, jwt: c.buyerJwt);
    a4GetAfter = await c.storageGetSigned(a4Signed);
  }
  final a4Reuse = a4Signed != null &&
      a4GetBefore.ok &&
      (a4Del.ok || a4Del.status == 200 || a4Del.status == 204) &&
      a4GetAfter.ok &&
      !isDenied(a4GetAfter) &&
      a4GetAfter.body.contains('PNG');
  c.note('A4.revoke', 'sign → delete → GET signed', {
    'up': a4Up.brief,
    'before': a4GetBefore.brief,
    'del': a4Del.brief,
    'after': a4GetAfter.brief,
  }, lens: 'DQ6');
  denyOrHold(
    id: 'DQ-A4.signed_reuse_after_delete',
    matrix: 'DQ-A',
    lens: 'DQ6',
    payload: 'sign PNG próprio → DELETE object → GET mesma signed URL',
    hit: a4GetAfter,
    bd: 'before=${a4GetBefore.status} del=${a4Del.status} after=${a4GetAfter.status} reuse=$a4Reuse',
    expectedDeny: '404/400 NoSuchKey após delete',
    classeNova: true,
    persistedOverride: a4Reuse,
    title: 'signed URL válida após revoke',
    severity: 'P1',
  );

  // A5 classe nova: unicode slash U+2AFB ⫻ (não está no loop canonical)
  const tripleSolidus = '\u2afb';
  final a5Url =
      '$signedOrOwn${tripleSolidus}order_disputes/${c.buyer2Id}/00000000-0000-0000-0000-00000000dq02/rtdq-secret.png';
  final a5Canon = await canonRpc(a5Url);
  final a5Ok = await proofOkRpc(a5Url, c.buyerId!, hp.oid);
  denyOrHold(
    id: 'DQ-A5.unicode_triple_solidus_2afb',
    matrix: 'DQ-A',
    lens: 'DQ1',
    payload: 'proof URL signed + U+2AFB TRIPLE SOLIDUS + path B2',
    hit: a5Ok,
    bd: 'canon=${clip(a5Canon.body, 120)} rpc=${a5Ok.body}',
    expectedDeny: 'proof_ok false (slash unicode novo)',
    classeNova: true,
    persistedOverride: rpcTrue(a5Ok),
    title: 'unicode slash U+2AFB na prova',
  );

  // A5b overlong double-encoded %25c0%25af (não o %c0%af já no loop)
  final a5bUrl =
      '$signedOrOwn%25c0%25aforder_disputes/${c.buyer2Id}/00000000-0000-0000-0000-00000000dq02/rtdq-secret.png';
  final a5bCanon = await canonRpc(a5bUrl);
  final a5bOk = await proofOkRpc(a5bUrl, c.buyerId!, hp.oid);
  denyOrHold(
    id: 'DQ-A5b.overlong_double_pct25c0af',
    matrix: 'DQ-A',
    lens: 'DQ1',
    payload: 'proof URL + %25c0%25af (overlong UTF-8 duplo) + path B2',
    hit: a5bOk,
    bd: 'canon=${clip(a5bCanon.body, 120)} rpc=${a5bOk.body}',
    expectedDeny: 'false (overlong não vira / útil, ou deny concat)',
    classeNova: true,
    persistedOverride: rpcTrue(a5bOk),
    title: 'overlong UTF-8 duplo %25c0%25af',
  );

  // A5c null omit %00 (sem chr(0) literal — Postgres 54000)
  final a5cUrl =
      '$signedOrOwn%00order_disputes/${c.buyer2Id}/00000000-0000-0000-0000-00000000dq02/rtdq-secret.png';
  final a5cCanon = await canonRpc(a5cUrl);
  final a5cOk = await proofOkRpc(a5cUrl, c.buyerId!, hp.oid);
  final a5cBoom = '${a5cCanon.body}${a5cOk.body}'.contains('54000');
  c.note('A5c.nul', 'pct00 omit', {
    'canon': a5cCanon.brief,
    'rpc': a5cOk.brief,
    '54000': a5cBoom,
  }, lens: 'DQ1');
  denyOrHold(
    id: 'DQ-A5c.null_omit_pct00',
    matrix: 'DQ-A',
    lens: 'DQ1',
    payload: 'proof URL + %00 (percent, sem chr(0) literal) + path B2',
    hit: a5cOk,
    bd: 'canon=${clip(a5cCanon.body, 120)} rpc=${a5cOk.body} 54000=$a5cBoom',
    expectedDeny: 'false; 54000 documentado se rebentar',
    classeNova: true,
    persistedOverride: rpcTrue(a5cOk),
    title: 'null omit %00 na prova',
  );

  // ===========================================================================
  // DQ-D1 happy pago + label (antes de B* para ter disputa própria)
  // ===========================================================================
  final d1Ins = await c.insertDispute(orderId: hp.oid, photos: [signedOrOwn]);
  var did = d1Ins.firstId;
  passHappy(
    id: 'DQ-D1.pago_label_feliz',
    matrix: 'DQ-D',
    lens: 'DQ6',
    payload: 'POST order_disputes proof signed própria em concluido',
    hit: d1Ins,
    bd: 'id=$did photos=${clip(d1Ins.map?['proof_photos'], 120)}',
    ok: d1Ins.status == 201 && did != null,
    title: 'disputa+prova signed 201',
  );

  HttpHit d1Label = HttpHit(0, 'no_dispute', null);
  if (did != null) {
    d1Label = await c.patchDispute(did, {'return_label_url': signedOrOwn});
  }
  passHappy(
    id: 'DQ-D1b.label_canonical',
    matrix: 'DQ-D',
    lens: 'DQ6',
    payload: 'PATCH return_label_url signed própria',
    hit: d1Label,
    bd: 'url=${clip(d1Label.map?['return_label_url'], 140)}',
    ok: d1Label.ok &&
        (d1Label.map?['return_label_url']?.toString().isNotEmpty ?? false),
    title: 'label signed 200',
  );

  // CTRL anti-atrofia: label %252f deve DENY agora (fecho DG/DBDG)
  if (did != null) {
    final ctrl252f =
        '${signedOrOwn}%252forder_disputes/${c.buyer2Id}/00000000-0000-0000-0000-00000000dq02/rtdq-secret.png';
    final ctrlHit =
        await c.patchDispute(did, {'return_label_url': ctrl252f});
    final stored = await c.disputeRow(did);
    final persisted252f =
        ctrlHit.ok &&
            '${stored?['return_label_url'] ?? ''}'.contains('%252f');
    denyOrHold(
      id: 'DQ-CTRL.label_252f',
      matrix: 'DQ-A',
      lens: 'DQ1',
      payload: 'PATCH label %252f simples + path B2 (anti-atrofia: expect deny)',
      hit: ctrlHit,
      bd: 'stored=${clip(stored?['return_label_url'], 140)} persisted=$persisted252f',
      expectedDeny: '400 order_dispute_label_url_denied',
      residual: true,
      persistedOverride: persisted252f,
      title: 'label %252f residual',
    );

    final ctrlSlash =
        '${signedOrOwn.replaceFirst('/ok.png', '/ok.png')}//extra.png';
    final slashHit =
        await c.patchDispute(did, {'return_label_url': ctrlSlash});
    denyOrHold(
      id: 'DQ-CTRL.slashslash_after_host',
      matrix: 'DQ-A',
      lens: 'DQ1',
      payload: 'PATCH label signed + //extra.png após ficheiro',
      hit: slashHit,
      bd: 'stored after=${clip((await c.disputeRow(did))?['return_label_url'], 100)}',
      expectedDeny: '400 // após host',
      residual: true,
      title: '// após host residual',
    );
  }

  // A5 persist attempt on existing dispute (label) with unicode nova
  if (did != null) {
    final a5Patch = await c.patchDispute(did, {'return_label_url': a5Url});
    final a5Stored = await c.disputeRow(did);
    denyOrHold(
      id: 'DQ-A5d.label_unicode_2afb',
      matrix: 'DQ-A',
      lens: 'DQ1',
      payload: 'PATCH label U+2AFB + path B2',
      hit: a5Patch,
      bd: 'stored=${clip(a5Stored?['return_label_url'], 140)}',
      expectedDeny: '400 label_url_denied',
      classeNova: true,
      persistedOverride: a5Patch.ok &&
          '${a5Stored?['return_label_url'] ?? ''}'.contains('\u2afb'),
      title: 'label unicode U+2AFB persistida',
    );
  }

  // ===========================================================================
  // DQ-B Disputa FSM (≥4)
  // ===========================================================================

  // B1 disputa order alheia
  final alienPaid = await mustPay('DQ2', qty: 1);
  if (!await c.toEnviado(alienPaid.oid)) throw StateError('env alien');
  if (!await c.toConcluido(alienPaid.oid)) throw StateError('conc alien');
  final b1 = await c.insertDispute(
    orderId: alienPaid.oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  denyOrHold(
    id: 'DQ-B1.dispute_order_alheia',
    matrix: 'DQ-B',
    lens: 'DQ2',
    payload: 'B2 POST order_disputes na order paga de B1',
    hit: b1,
    bd: 'oid=${alienPaid.oid} id=${b1.firstId}',
    expectedDeny: '403 RLS / buyer_id mismatch',
    title: 'disputa order alheia',
  );

  // B2 disputa fora de janela — residual 403 após release (não contar HOLD)
  final win = await mustPay('DQ3', qty: 1);
  if (!await c.toEnviado(win.oid)) throw StateError('env win');
  if (!await c.toConcluido(win.oid)) throw StateError('conc win');
  await c.patchOrder(win.oid, {
    'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String(),
  }, service: true);
  final b2 = await c.insertDispute(orderId: win.oid);
  denyOrHold(
    id: 'DQ-B2.window_after_release',
    matrix: 'DQ-B',
    lens: 'DQ3',
    payload: 'POST disputa após wallet_release_processed_at (fixture svc)',
    hit: b2,
    bd: 'oid=${win.oid} released=svc id=${b2.firstId}',
    expectedDeny: '403 residual janela',
    residual: true,
    title: 'disputa fora de janela pós-release',
  );

  // B2b classe_nova janela: disputa em enviado (não concluido)
  final envOnly = await mustPay('DQ3', qty: 1);
  if (!await c.toEnviado(envOnly.oid)) throw StateError('env only');
  final b2b = await c.insertDispute(orderId: envOnly.oid);
  denyOrHold(
    id: 'DQ-B2b.window_enviado_not_concluido',
    matrix: 'DQ-B',
    lens: 'DQ3',
    payload: 'POST disputa em status=enviado (ainda não concluido)',
    hit: b2b,
    bd: 'status=${(await c.orderRow(envOnly.oid))?['status']} id=${b2b.firstId}',
    expectedDeny: '403 só concluido/entregue',
    classeNova: true,
    title: 'disputa na janela enviado',
  );

  // B2c classe_nova: JWT backdate completed_at 60d + disputa ainda unreleased
  final aged = await mustPay('DQ3', qty: 1);
  if (!await c.toEnviado(aged.oid)) throw StateError('env aged');
  if (!await c.toConcluido(aged.oid)) throw StateError('conc aged');
  final agedAt = DateTime.now().toUtc().subtract(const Duration(days: 60));
  final agePatch = await c.patchOrder(aged.oid, {
    'completed_at': agedAt.toIso8601String(),
  });
  final agedRow = await c.orderRow(aged.oid);
  final b2c = await c.insertDispute(orderId: aged.oid);
  c.note('B2c.backdate', 'JWT completed_at 60d', {
    'patch': agePatch.brief,
    'completed_at': agedRow?['completed_at'],
    'dispute': b2c.brief,
  }, lens: 'DQ3');
  // HOLD só se PATCH JWT alterou completed_at E isso reabre/fecha janela de forma hostil.
  // Disputa 201 com completed_at antigo + release null = sem janela calendário (documentar FAIL).
  final completedParsed = DateTime.tryParse('${agedRow?['completed_at'] ?? ''}');
  final jwtMovedCompleted = agePatch.ok &&
      !emptyOk(agePatch) &&
      completedParsed != null &&
      completedParsed.isBefore(
          DateTime.now().toUtc().subtract(const Duration(days: 30)));
  denyOrHold(
    id: 'DQ-B2c.jwt_backdate_completed_at',
    matrix: 'DQ-B',
    lens: 'DQ3',
    payload: 'JWT PATCH completed_at −60d depois disputa',
    hit: agePatch,
    bd: 'completed_at=${agedRow?['completed_at']} dispute=${b2c.status} jwtMoved=$jwtMovedCompleted',
    expectedDeny: '42501 completed_at immutable; disputa segue RLS (concluido+unreleased)',
    classeNova: true,
    persistedOverride: jwtMovedCompleted,
    title: 'JWT backdate completed_at',
    severity: 'P2',
  );
  if (b2c.status == 201) {
    c.note('B2c.dispute_ok', 'disputa 201 com completed_at antigo — sem janela calendário RLS',
        b2c.brief,
        lens: 'DQ3');
  }

  // B3 disputa ∥ refund race
  final race = await mustPay('DQ4', qty: 1);
  if (!await c.toEnviado(race.oid)) throw StateError('env race');
  if (!await c.toConcluido(race.oid)) throw StateError('conc race');
  final qty0 = await c.productRow(race.pid);
  final q0 = numOf(qty0?['quantity'])?.round() ?? -1;
  final w0 = await c.wallets();
  final raced = await parallel([
    c.insertDispute(orderId: race.oid, photos: [signedOrOwn]),
    c.refund(race.oid),
  ]);
  final dRace = raced[0];
  final rfRace = raced[1];
  final qty1 = await c.productRow(race.pid);
  final q1 = numOf(qty1?['quantity'])?.round() ?? -1;
  final w1 = await c.wallets();
  final raceRow = await c.orderRow(race.oid);
  final bothWon = dRace.status == 201 &&
      rfRace.ok &&
      !isDenied(rfRace) &&
      q1 > q0 &&
      ((w1['seller'] ?? 0) - (w0['seller'] ?? 0) != 0 ||
          (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0) != 0);
  c.note('B3.race', 'disputa∥refund', {
    'd': dRace.brief,
    'rf': rfRace.brief,
    'qty': '$q0→$q1',
    'status': raceRow?['status'],
    'refund_id': raceRow?['stripe_refund_id'],
    'Δb': (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0),
    'Δs': (w1['seller'] ?? 0) - (w0['seller'] ?? 0),
  }, lens: 'DQ4');
  denyOrHold(
    id: 'DQ-B3.dispute_refund_race',
    matrix: 'DQ-B',
    lens: 'DQ4',
    payload: 'Future.wait POST disputa ∥ Edge refund-order',
    hit: bothWon ? rfRace : (dRace.status == 201 ? dRace : rfRace),
    bd: 'd=${dRace.status} rf=${rfRace.status} qty $q0→$q1 bothWon=$bothWon st=${raceRow?['status']}',
    expectedDeny: 'XOR: disputa 201 e refund 403, ou refund 200 e disputa 403; stock +1 no máximo uma vez',
    persistedOverride: bothWon,
    title: 'race disputa∥refund cria dinheiro+stock',
    severity: 'P0',
  );
  c.probe(
    id: 'DQ-B3b.race_oracles',
    matrix: 'DQ-B',
    payload: 'oráculos stock/wallet/status após race',
    http: 'd=${dRace.status} rf=${rfRace.brief}',
    bd: 'qty $q0→$q1 Δb=${(w1['buyer'] ?? 0) - (w0['buyer'] ?? 0)} Δs=${(w1['seller'] ?? 0) - (w0['seller'] ?? 0)} refund=${raceRow?['stripe_refund_id']}',
    result: bothWon ? 'HOLD' : 'FAIL',
  );

  // B4 open disputa + PATCH status hostil
  if (did != null) {
    final b4d = await c.patchDispute(did, {'status': 'resolvida'});
    final b4row = await c.disputeRow(did);
    final b4o = await c.patchOrder(hp.oid, {'status': 'cancelado'});
    final b4or = await c.orderRow(hp.oid);
    final hostile = (b4d.ok &&
            !emptyOk(b4d) &&
            b4row?['status']?.toString() == 'resolvida') ||
        (b4o.ok &&
            !emptyOk(b4o) &&
            b4or?['status']?.toString() == 'cancelado');
    denyOrHold(
      id: 'DQ-B4.patch_hostile_status',
      matrix: 'DQ-B',
      lens: 'DQ2',
      payload: 'buyer PATCH disputa status=resolvida + order status=cancelado',
      hit: hostile ? (b4d.ok && !emptyOk(b4d) ? b4d : b4o) : b4d,
      bd: 'disp=${b4row?['status']} order=${b4or?['status']} dHit=${b4d.brief} oHit=${b4o.brief}',
      expectedDeny: '403/200[] status disputa/order inalterado',
      persistedOverride: hostile,
      title: 'PATCH status hostil com disputa aberta',
      severity: 'P1',
    );
  }

  // ===========================================================================
  // DQ-C Shipping (≥3)
  // ===========================================================================

  // C1 PATCH shipping após cs_ open
  final c1sku = await c.createProduct(title: '$prefix-c1', qty: 2);
  String? c1oid;
  if (c1sku != null) {
    c1oid = await c.insertOrder(
      productId: c1sku,
      jwt: c.buyerJwt,
      shipping: 'entrega em mão',
    );
  }
  HttpHit c1cs = HttpHit(0, 'no_order', null);
  HttpHit c1patch = HttpHit(0, 'no_order', null);
  Map<String, dynamic>? c1before;
  Map<String, dynamic>? c1after;
  if (c1oid != null) {
    c1cs = await c.checkout(
      orderId: c1oid,
      productId: c1sku,
      amount: 1,
      shipping: 'mao',
    );
    c1before = await c.orderRow(c1oid);
    c1patch = await c.patchOrder(c1oid, {'shipping_method': 'ctt'});
    c1after = await c.orderRow(c1oid);
  }
  final c1Changed = c1after != null &&
      '${c1after['shipping_method']}' != '${c1before?['shipping_method']}' &&
      '${c1after['shipping_method']}'.toLowerCase().contains('ctt');
  c.note('C1.cs', 'PATCH ship após Session', {
    'cs': c1cs.brief,
    'sid': c1before?['stripe_checkout_session_id'],
    'before': c1before?['shipping_method'],
    'patch': c1patch.brief,
    'after': c1after?['shipping_method'],
  }, lens: 'DQ5');
  denyOrHold(
    id: 'DQ-C1.patch_ship_after_cs',
    matrix: 'DQ-C',
    lens: 'DQ5',
    payload: 'após create-payment-intent (cs_) JWT PATCH shipping_method=ctt',
    hit: c1patch,
    bd: 'sid=${c1before?['stripe_checkout_session_id']} ${c1before?['shipping_method']}→${c1after?['shipping_method']} changed=$c1Changed',
    expectedDeny: '42501 frozen ou selo revertido (mão intacto)',
    persistedOverride: c1Changed,
    title: 'selo portes após Session open',
    severity: 'P1',
  );

  // C2 PATCH shipping após pago
  final c2 = await mustPay('DQ5', qty: 1);
  final c2b = await c.orderRow(c2.oid);
  final c2p = await c.patchOrder(c2.oid, {'shipping_method': 'ctt'});
  final c2a = await c.orderRow(c2.oid);
  final c2Changed = '${c2a?['shipping_method']}' != '${c2b?['shipping_method']}' &&
      '${c2a?['shipping_method']}'.toLowerCase().contains('ctt');
  denyOrHold(
    id: 'DQ-C2.patch_ship_after_pago',
    matrix: 'DQ-C',
    lens: 'DQ5',
    payload: 'order paga JWT PATCH shipping_method=ctt',
    hit: c2p,
    bd: '${c2b?['shipping_method']}→${c2a?['shipping_method']} paid=${c2a?['amount_paid_cents']}',
    expectedDeny: '42501 order_shipping_frozen_after_payment',
    persistedOverride: c2Changed,
    title: 'selo portes após pago',
    severity: 'P1',
  );

  // C3 bag lines shipping misturado — classe_nova
  final mixA = await c.createProduct(title: '$prefix-mixA', qty: 2);
  final mixB = await c.createProduct(title: '$prefix-mixB', qty: 2);
  String? mixOidA;
  String? mixOidB;
  if (mixA != null) {
    mixOidA = await c.insertOrder(
      productId: mixA,
      jwt: c.buyerJwt,
      shipping: 'Envio transportadora (€3.50)',
    );
  }
  if (mixB != null) {
    mixOidB = await c.insertOrder(
      productId: mixB,
      jwt: c.buyerJwt,
      shipping: 'entrega em mão',
    );
  }
  HttpHit mixHit = HttpHit(0, 'no_bag', null);
  if (mixOidA != null && mixOidB != null) {
    mixHit = await c.checkoutBag(
      lines: [
        {'order_id': mixOidA, 'product_id': mixA, 'quantity': 1},
        {'order_id': mixOidB, 'product_id': mixB, 'quantity': 1},
      ],
      amount: 1,
      shipping: 'mao',
    );
  }
  final mixAmt = mixHit.amountTotal;
  final mixCheap = mixHit.ok && mixAmt != null && mixAmt < 1400;
  c.note('C3.mix', 'bag CTT+mão body=mao', {
    'hit': mixHit.brief,
    'amt': mixAmt,
    'a': mixOidA == null ? null : (await c.orderRow(mixOidA))?['shipping_method'],
    'b': mixOidB == null ? null : (await c.orderRow(mixOidB))?['shipping_method'],
  }, lens: 'DQ5');
  denyOrHold(
    id: 'DQ-C3.bag_mixed_shipping',
    matrix: 'DQ-C',
    lens: 'DQ5',
    payload: 'bag CTT(3,50)+mão; body shipping=mao amount=1',
    hit: mixHit,
    bd: 'amt=$mixAmt cheap=$mixCheap a=${mixOidA} b=${mixOidB}',
    expectedDeny: 'portes = max selos (≥350¢ CTT) + itens; não cair para mão',
    classeNova: true,
    persistedOverride: mixCheap,
    title: 'saco portes misturados subcotados',
    severity: 'P1',
  );

  // ===========================================================================
  // DQ-D2 seller marca enviado sem prova
  // ===========================================================================
  final d2 = await mustPay('DQ5', qty: 1);
  final d2b = await c.orderRow(d2.oid);
  final d2p = await c.patchOrder(d2.oid, {'status': 'enviado'});
  final d2a = await c.orderRow(d2.oid);
  final d2ok = d2a?['status']?.toString() == 'enviado';
  c.note('D2.ship_noproof', 'seller enviado sem proof_url', {
    'before_proof': d2b?['proof_url'],
    'hit': d2p.brief,
    'status': d2a?['status'],
    'shipped_at': d2a?['shipped_at'],
    'rule': d2ok
        ? 'REGRA: após pago, seller pode marcar enviado sem tracking/prova'
        : 'REGRA: enviado exige prova — deny',
  }, lens: 'DQ5');
  // Documentar regra — não é finding se 200 (desenho: captura basta).
  // HOLD só se enviado SEM pago (já pago aqui).
  passHappy(
    id: 'DQ-D2.seller_enviado_sem_prova',
    matrix: 'DQ-D',
    lens: 'DQ5',
    payload: 'seller PATCH enviado em pago sem proof_url/tracking',
    hit: d2p,
    bd: 'proof=${d2b?['proof_url']} status=${d2a?['status']} shipped_at=${d2a?['shipped_at']}',
    ok: d2ok,
    title: 'enviado sem prova após pago (regra documentada)',
  );

  // Stock pós-refund oráculo (se B3 refundou)
  if (rfRace.ok && !isDenied(rfRace)) {
    c.lensesHit.add('DQ7');
  } else {
    final rfExtra = await mustPay('DQ7', qty: 1);
    final qPre = numOf((await c.productRow(rfExtra.pid))?['quantity'])?.round();
    final rfH = await c.refund(rfExtra.oid);
    final qPost = numOf((await c.productRow(rfExtra.pid))?['quantity'])?.round();
    final st = (await c.orderRow(rfExtra.oid))?['status'];
    c.note('DQ7.refund_stock', 'refund pago → stock', {
      'rf': rfH.brief,
      'qty': '$qPre→$qPost',
      'status': st,
    }, lens: 'DQ7');
    c.probe(
      id: 'DQ-D3.refund_stock_oracle',
      matrix: 'DQ-D',
      payload: 'refund-order em pago (sem disputa) + stock',
      http: rfH.brief,
      bd: 'qty $qPre→$qPost status=$st',
      result: (qPost != null && qPre != null && qPost == qPre + 1) ||
              isDenied(rfH)
          ? 'FAIL'
          : 'HOLD',
    );
  }

  await c.dumpAll('pass1.json');
  stdout.writeln(
      'DONE probes=${c.probes.length} findings=${c.findings.length} lenses=${c.lensesHit.toList()..sort()}');
}
