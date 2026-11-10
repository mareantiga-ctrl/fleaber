/// RED TEAM CEGO DV — storage / disputa / label / shipping pós-DNDS.
/// Staging only. Não corrige. Matriz A≥6 B≥4 C≥4 D≥2 · ≥4 classe_nova · quota ≥16.
import 'dart:convert';
import 'dart:io';
import '_rtdv.dart';

const pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

const svgPolyglot = '''
<?xml version="1.0"?>
<svg xmlns="http://www.w3.org/2000/svg">
<script>alert(1)</script>
</svg>
''';

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
      raw.contains('invalidkey') ||
      raw.contains('revoke_forbidden') ||
      raw.contains('rls');
}

bool emptyOk(HttpHit h) {
  if (h.status == 204) return true;
  if (!h.ok) return false;
  if (h.list.isEmpty && h.map == null && (h.body.isEmpty || h.body == '[]')) {
    return true;
  }
  return false;
}

bool rpcFalse(HttpHit h) => h.body.trim() == 'false' || h.json == false;
bool rpcTrue(HttpHit h) => h.body.trim() == 'true' || h.json == true;

void main() async {
  final c = Rtdv.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  c.well('DV-A');
  c.well('DV-B');
  c.well('DV-C');
  c.well('DV-D');

  Future<({String oid, String pid, String? pi})> mustPay(String lens,
      {int qty = 1}) async {
    final paid = await c.payToPago(lens: lens, initialQty: qty);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
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
    final persisted =
        persistedOverride || (hit.ok && !isDenied(hit) && !emptyOk(hit));
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
        severity: 'P2',
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

  final hp = await mustPay('DV1', qty: 1);
  if (!await c.toEnviado(hp.oid)) throw StateError('enviado hp');
  if (!await c.toConcluido(hp.oid)) throw StateError('concluido hp');

  final minePath = c.disputeObj(c.buyerId!, hp.oid, 'ok.png');
  final up = await c.storageUpload(
    objectName: minePath,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final signed = await c.signObject(minePath, jwt: c.buyerJwt);
  c.note('DV1.upload', 'PNG próprio assinado', {
    'up': up.brief,
    'signed': signed,
    'path': minePath,
  }, lens: 'DV1');

  final alienKey =
      'order_disputes/${c.buyer2Id}/00000000-0000-0000-0000-00000000dv02/rtdv-secret.png';
  final alienUp = await c.storageUpload(
    objectName: alienKey,
    bytes: pngBytes,
    jwt: c.buyer2Jwt,
  );
  c.note('DV1.alien', 'objecto B2', alienUp.brief, lens: 'DV1');

  String ownSign(String file) =>
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/${c.buyerId}/${hp.oid}/$file';
  final signedOrOwn = signed ?? ownSign('ok.png');

  // ===========================================================================
  // DV-A Storage / path (≥6)
  // ===========================================================================

  // A1 upload ../ outro buyer
  final a1Name =
      'order_disputes/${c.buyerId}/../${c.buyer2Id}/rtdv-dotdot.png';
  final a1Up = await c.storageUpload(
    objectName: a1Name,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final a1GetAlien = await c.storageGet(
    'order_disputes/${c.buyer2Id}/rtdv-dotdot.png',
    jwt: c.buyerJwt,
  );
  final a1Loot = a1Up.ok &&
      !isDenied(a1GetAlien) &&
      (a1GetAlien.body.contains('PNG') || a1GetAlien.status == 200);
  denyOrHold(
    id: 'DV-A1.path_dotdot_upload',
    matrix: 'DV-A',
    lens: 'DV1',
    payload: 'POST object order_disputes/{B1}/../{B2}/rtdv-dotdot.png',
    hit: a1Loot ? a1GetAlien : a1Up,
    bd: 'up=${a1Up.status} getAlien=${a1GetAlien.status} loot=$a1Loot',
    expectedDeny: '403 RLS / sem GET no prefixo B2',
    persistedOverride: a1Loot,
    title: 'traversal ../ no storage',
  );

  // A2 unicode slash NOVO U+FF0F FULLWIDTH SOLIDUS (não U+2AFB do DQ)
  const fullwidth = '\uff0f';
  final a2Url =
      '$signedOrOwn${fullwidth}order_disputes/${c.buyer2Id}/00000000-0000-0000-0000-00000000dv02/rtdv-secret.png';
  final a2Ok = await proofOkRpc(a2Url, c.buyerId!, hp.oid);
  denyOrHold(
    id: 'DV-A2.unicode_ff0f_fullwidth',
    matrix: 'DV-A',
    lens: 'DV1',
    payload: 'proof URL signed + U+FF0F FULLWIDTH SOLIDUS + path B2',
    hit: a2Ok,
    bd: 'rpc=${a2Ok.body}',
    expectedDeny: 'proof_ok false',
    classeNova: true,
    persistedOverride: rpcTrue(a2Ok),
    title: 'unicode slash U+FF0F na prova',
  );

  // A3 signed URL buyer2 em disputa buyer1
  final a3Signed = await c.signObject(alienKey, jwt: c.buyer2Jwt);
  final a3Url = a3Signed ??
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$alienKey';
  final a3Ok = await proofOkRpc(a3Url, c.buyerId!, hp.oid);
  final a3Get = await c.storageGet(alienKey, jwt: c.buyerJwt);
  denyOrHold(
    id: 'DV-A3.signed_url_buyer2',
    matrix: 'DV-A',
    lens: 'DV3',
    payload: 'RPC proof_ok URL signed B2 em disputa B1 + GET objecto B2 como B1',
    hit: a3Ok,
    bd: 'rpc=${a3Ok.body} getB2asB1=${a3Get.brief}',
    expectedDeny: 'rpc false + GET NoSuchKey/403',
    persistedOverride: rpcTrue(a3Ok) || (a3Get.ok && !isDenied(a3Get)),
    title: 'URL prova outro buyer',
  );

  // A4 DELETE + auth GET 404 + revoke RPC + proof_ok  (classe_nova DNDS)
  final a4Path = c.disputeObj(c.buyerId!, hp.oid, 'revoke.png');
  final a4Up = await c.storageUpload(
    objectName: a4Path,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final a4Signed = await c.signObject(a4Path, jwt: c.buyerJwt);
  HttpHit a4GetBefore = HttpHit(0, 'no_sign', null);
  if (a4Signed != null) {
    a4GetBefore = await c.storageGetSigned(a4Signed);
  }
  final a4Del = await c.storageDelete(a4Path, jwt: c.buyerJwt);
  final a4AuthAfter = await c.storageGet(a4Path, jwt: c.buyerJwt);
  final a4Rev = await c.revokePath(a4Path, jwt: c.buyerJwt);
  final a4ProofUrl = a4Signed ?? ownSign('revoke.png');
  final a4OkAfter = await proofOkRpc(a4ProofUrl, c.buyerId!, hp.oid);
  final a4AuthGone = isDenied(a4AuthAfter) || a4AuthAfter.status == 404;
  final a4ProofStillTrue = rpcTrue(a4OkAfter);
  c.note('A4.revoke', 'DELETE + revoke RPC + proof_ok', {
    'up': a4Up.brief,
    'before': a4GetBefore.brief,
    'del': a4Del.brief,
    'authAfter': a4AuthAfter.brief,
    'rev': a4Rev.brief,
    'proof_ok': a4OkAfter.body,
  }, lens: 'DV2');
  // HOLD se auth GET ainda 200 OU proof_ok ainda true após revoke.
  denyOrHold(
    id: 'DV-A4.delete_revoke_proof_ok',
    matrix: 'DV-A',
    lens: 'DV2',
    payload:
        'upload → sign → DELETE → auth GET + RPC batata_revoke_private_object + proof_ok',
    hit: a4OkAfter,
    bd: 'del=${a4Del.status} authAfter=${a4AuthAfter.status} rev=${a4Rev.body} proof_ok=${a4OkAfter.body} authGone=$a4AuthGone',
    expectedDeny: 'auth GET 404; revoke true; proof_ok false',
    classeNova: true,
    persistedOverride: !a4AuthGone || a4ProofStillTrue,
    title: 'revoke RPC não apaga proof_ok / objecto ainda visível',
    severity: 'P2',
  );

  // A5 signed GET pós-DELETE (CDN residual — máx 1 HOLD se 200)
  HttpHit a5SignedGet = HttpHit(0, 'no_sign', null);
  if (a4Signed != null) {
    a5SignedGet = await c.storageGetSigned(a4Signed);
  }
  final a5Cdn200 = a5SignedGet.ok &&
      !isDenied(a5SignedGet) &&
      (a5SignedGet.body.contains('PNG') || a5SignedGet.status == 200);
  c.note('A5.cdn', 'signed GET pós-DELETE', {
    'signed': a4Signed,
    'get': a5SignedGet.brief,
    'cdn200': a5Cdn200,
  }, lens: 'DV2');
  denyOrHold(
    id: 'DV-A5.signed_get_after_delete',
    matrix: 'DV-A',
    lens: 'DV2',
    payload: 'GET da mesma signed URL após DELETE+revoke (CDN residual)',
    hit: a5SignedGet,
    bd: 'auth=${a4AuthAfter.status} signed=${a5SignedGet.status} cdn200=$a5Cdn200',
    expectedDeny: '404/400; se 200 = residual plataforma (máx 1 HOLD)',
    classeNova: true,
    residual: true,
    persistedOverride: a5Cdn200,
    title: 'signed CDN 200 pós-DELETE',
  );
  if (a5Cdn200) {
    c.hold(
      id: 'DV-A5.signed_get_after_delete',
      lens: 'DV2',
      severity: 'P2',
      title: 'signed CDN 200 pós-DELETE (residual plataforma)',
      actor: 'buyer JWT (objecto próprio)',
      pre: 'sign → DELETE → GET signed antiga',
      repro: 'DV-A5.signed_get_after_delete',
      expected: '404 após DELETE+revoke',
      obtained: a5SignedGet.brief,
    );
  }

  // A6 mime JS / polyglot SVG
  final a6Path = c.disputeObj(c.buyerId!, hp.oid, 'poly.svg');
  final a6Up = await c.storageUpload(
    objectName: a6Path,
    bytes: utf8.encode(svgPolyglot),
    jwt: c.buyerJwt,
    contentType: 'image/svg+xml',
  );
  final a6Sign = await c.signObject(a6Path, jwt: c.buyerJwt);
  final a6Url = a6Sign ?? ownSign('poly.svg');
  final a6Ok = await proofOkRpc(a6Url, c.buyerId!, hp.oid);
  final a6Accept = a6Up.ok && rpcTrue(a6Ok);
  c.note('A6.svg', 'SVG polyglot', {
    'up': a6Up.brief,
    'rpc': a6Ok.body,
  }, lens: 'DV1');
  denyOrHold(
    id: 'DV-A6.mime_svg_polyglot',
    matrix: 'DV-A',
    lens: 'DV1',
    payload: 'upload poly.svg CT=image/svg+xml com <script> + proof_ok',
    hit: a6Ok,
    bd: 'up=${a6Up.status} rpc=${a6Ok.body} accept=$a6Accept',
    expectedDeny: 'upload 4xx/415 ou proof_ok false (não imagem raster)',
    classeNova: true,
    persistedOverride: a6Accept,
    title: 'SVG polyglot aceite como prova',
  );

  // A7 classe_nova: INSERT directo na tabela revoke (bypass RPC ownership)
  final a7AlienPath =
      'order_disputes/${c.buyer2Id}/${hp.oid}/hostile-revoke.png';
  final a7Ins = await c.revokedInsert(a7AlienPath, jwt: c.buyerJwt);
  final a7Sel = await c.revokedSelect(jwt: c.buyerJwt);
  final a7SelSvc = await c.revokedSelect(service: true);
  final a7Wrote = a7Ins.ok && !isDenied(a7Ins) && !emptyOk(a7Ins);
  final a7Leak = a7Sel.ok &&
      !isDenied(a7Sel) &&
      a7Sel.list.isNotEmpty &&
      a7Sel.list.any((e) =>
          e is Map && '${e['object_path']}'.contains('${c.buyer2Id}'));
  c.note('A7.table', 'INSERT/SELECT batata_private_object_revoked', {
    'ins': a7Ins.brief,
    'selJwt': a7Sel.brief,
    'selSvcN': a7SelSvc.list.length,
  }, lens: 'DV2');
  denyOrHold(
    id: 'DV-A7.revoke_table_direct_insert',
    matrix: 'DV-A',
    lens: 'DV2',
    payload:
        'JWT B1 POST batata_private_object_revoked path de B2 (bypass RPC)',
    hit: a7Ins,
    bd: 'ins=${a7Ins.brief} selJwt=${a7Sel.status} n=${a7Sel.list.length} wrote=$a7Wrote leak=$a7Leak',
    expectedDeny: '403 RLS / 42501; só RPC dono do prefixo',
    classeNova: true,
    persistedOverride: a7Wrote || a7Leak,
    title: 'INSERT directo no revoke registry alheio',
    severity: 'P1',
  );

  // A8 classe_nova: RPC revoke path alheio
  final a8 = await c.revokePath(alienKey, jwt: c.buyerJwt);
  denyOrHold(
    id: 'DV-A8.revoke_rpc_alien_path',
    matrix: 'DV-A',
    lens: 'DV2',
    payload: 'RPC batata_revoke_private_object path order_disputes/{B2}/…',
    hit: a8,
    bd: 'rpc=${a8.body}',
    expectedDeny: '42501 revoke_forbidden',
    classeNova: true,
    persistedOverride: rpcTrue(a8),
    title: 'revoke RPC path alheio',
    severity: 'P1',
  );

  // A9 classe_nova: storage COPY para prefixo B2
  final a9Dest =
      'order_disputes/${c.buyer2Id}/00000000-0000-0000-0000-00000000dv02/copied.png';
  final a9 = await c.storageCopy(
    sourceKey: minePath,
    destKey: a9Dest,
    jwt: c.buyerJwt,
  );
  final a9Get = await c.storageGet(a9Dest, jwt: c.buyerJwt);
  final a9Loot = a9.ok && !isDenied(a9) && a9Get.ok && !isDenied(a9Get);
  denyOrHold(
    id: 'DV-A9.storage_copy_alien_prefix',
    matrix: 'DV-A',
    lens: 'DV1',
    payload: 'POST /object/copy source=próprio dest=order_disputes/{B2}/…',
    hit: a9,
    bd: 'copy=${a9.brief} get=${a9Get.brief} loot=$a9Loot',
    expectedDeny: '403 RLS copy/dest',
    classeNova: true,
    persistedOverride: a9Loot,
    title: 'storage COPY para prefixo alheio',
    severity: 'P1',
  );

  // ===========================================================================
  // DV-D1 happy disputa (antes de B/C para ter disputa)
  // ===========================================================================
  final d1Ins = await c.insertDispute(orderId: hp.oid, photos: [signedOrOwn]);
  var did = d1Ins.firstId;
  passHappy(
    id: 'DV-D1.pago_proof_feliz',
    matrix: 'DV-D',
    lens: 'DV7',
    payload: 'POST order_disputes proof signed própria em concluido',
    hit: d1Ins,
    bd: 'id=$did photos=${clip(d1Ins.map?['proof_photos'], 120)}',
    ok: d1Ins.status == 201 && did != null,
    title: 'disputa+prova signed 201',
  );

  // Persist A2 unicode on existing dispute
  if (did != null) {
    final a2Patch = await c.patchDispute(did, {'return_label_url': a2Url});
    final a2Stored = await c.disputeRow(did);
    denyOrHold(
      id: 'DV-A2b.label_unicode_ff0f',
      matrix: 'DV-A',
      lens: 'DV6',
      payload: 'PATCH label U+FF0F + path B2',
      hit: a2Patch,
      bd: 'stored=${clip(a2Stored?['return_label_url'], 140)}',
      expectedDeny: '400 label_url_denied',
      classeNova: true,
      persistedOverride: a2Patch.ok &&
          '${a2Stored?['return_label_url'] ?? ''}'.contains(fullwidth),
      title: 'label unicode U+FF0F persistida',
    );
  }

  // CTRL anti-atrofia %252f e //  (não contar)
  if (did != null) {
    final ctrl252f =
        '${signedOrOwn}%252forder_disputes/${c.buyer2Id}/00000000-0000-0000-0000-00000000dv02/rtdv-secret.png';
    final ctrlHit =
        await c.patchDispute(did, {'return_label_url': ctrl252f});
    final stored = await c.disputeRow(did);
    final persisted252f =
        ctrlHit.ok && '${stored?['return_label_url'] ?? ''}'.contains('%252f');
    denyOrHold(
      id: 'DV-CTRL.label_252f',
      matrix: 'DV-A',
      lens: 'DV6',
      payload: 'PATCH label %252f + path B2 (anti-atrofia: expect deny)',
      hit: ctrlHit,
      bd: 'stored=${clip(stored?['return_label_url'], 140)} persisted=$persisted252f',
      expectedDeny: '400 order_dispute_label_url_denied',
      residual: true,
      persistedOverride: persisted252f,
      title: 'label %252f residual',
    );

    final slashHit = await c.patchDispute(
        did, {'return_label_url': '$signedOrOwn//extra.png'});
    denyOrHold(
      id: 'DV-CTRL.slashslash_after_host',
      matrix: 'DV-A',
      lens: 'DV6',
      payload: 'PATCH label signed + //extra.png após ficheiro',
      hit: slashHit,
      bd: 'stored after=${clip((await c.disputeRow(did))?['return_label_url'], 100)}',
      expectedDeny: '400 // após host',
      residual: true,
      title: '// após host residual',
    );
  }

  // A4b: persistir proof URL após revoke (se proof_ok ficou true)
  if (did != null && a4ProofStillTrue) {
    final a4b = await c.patchDispute(did, {
      'proof_photos': [a4ProofUrl],
    });
    final a4bRow = await c.disputeRow(did);
    final kept = '${a4bRow?['proof_photos']}'.contains('revoke.png');
    denyOrHold(
      id: 'DV-A4b.persist_revoked_proof',
      matrix: 'DV-A',
      lens: 'DV2',
      payload: 'PATCH proof_photos URL signed após DELETE+revoke',
      hit: a4b,
      bd: 'photos=${clip(a4bRow?['proof_photos'], 140)} kept=$kept',
      expectedDeny: '400 proof_ok false / dispute_proof_url_denied',
      classeNova: true,
      persistedOverride: a4b.ok && kept,
      title: 'prova revogada persiste na disputa',
      severity: 'P2',
    );
  }

  // ===========================================================================
  // DV-B Disputa FSM (≥4)
  // ===========================================================================

  // B1 disputa order alheia
  final alienPaid = await mustPay('DV3', qty: 1);
  if (!await c.toEnviado(alienPaid.oid)) throw StateError('env alien');
  if (!await c.toConcluido(alienPaid.oid)) throw StateError('conc alien');
  final b1 = await c.insertDispute(
    orderId: alienPaid.oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  denyOrHold(
    id: 'DV-B1.dispute_order_alheia',
    matrix: 'DV-B',
    lens: 'DV3',
    payload: 'B2 POST order_disputes na order paga de B1',
    hit: b1,
    bd: 'oid=${alienPaid.oid} id=${b1.firstId}',
    expectedDeny: '403 RLS / buyer_id mismatch',
    title: 'disputa order alheia',
  );

  // B2 disputa em enviado / pós-release (janela clássica = residual HOLD)
  final envOnly = await mustPay('DV4', qty: 1);
  if (!await c.toEnviado(envOnly.oid)) throw StateError('env only');
  final b2 = await c.insertDispute(orderId: envOnly.oid);
  denyOrHold(
    id: 'DV-B2.window_enviado',
    matrix: 'DV-B',
    lens: 'DV4',
    payload: 'POST disputa em status=enviado (ainda não concluido)',
    hit: b2,
    bd: 'status=${(await c.orderRow(envOnly.oid))?['status']} id=${b2.firstId}',
    expectedDeny: '403 só concluido/entregue',
    residual: true,
    title: 'disputa na janela enviado',
  );

  final win = await mustPay('DV4', qty: 1);
  if (!await c.toEnviado(win.oid)) throw StateError('env win');
  if (!await c.toConcluido(win.oid)) throw StateError('conc win');
  await c.patchOrder(win.oid, {
    'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String(),
  }, service: true);
  final b2r = await c.insertDispute(orderId: win.oid);
  denyOrHold(
    id: 'DV-B2b.window_after_release',
    matrix: 'DV-B',
    lens: 'DV4',
    payload: 'POST disputa após wallet_release_processed_at',
    hit: b2r,
    bd: 'oid=${win.oid} id=${b2r.firstId}',
    expectedDeny: '403 residual janela clássica',
    residual: true,
    title: 'disputa fora de janela pós-release',
  );

  // B2c classe_nova: JWT PATCH created_at disputa / completed_at order
  final aged = await mustPay('DV4', qty: 1);
  if (!await c.toEnviado(aged.oid)) throw StateError('env aged');
  if (!await c.toConcluido(aged.oid)) throw StateError('conc aged');
  final agedAt = DateTime.now().toUtc().subtract(const Duration(days: 60));
  final agePatch = await c.patchOrder(aged.oid, {
    'completed_at': agedAt.toIso8601String(),
  });
  final agedRow = await c.orderRow(aged.oid);
  final completedParsed = DateTime.tryParse('${agedRow?['completed_at'] ?? ''}');
  final jwtMovedCompleted = agePatch.ok &&
      !emptyOk(agePatch) &&
      completedParsed != null &&
      completedParsed.isBefore(
          DateTime.now().toUtc().subtract(const Duration(days: 30)));
  denyOrHold(
    id: 'DV-B2c.jwt_backdate_completed_at',
    matrix: 'DV-B',
    lens: 'DV4',
    payload: 'JWT PATCH completed_at −60d',
    hit: agePatch,
    bd: 'completed_at=${agedRow?['completed_at']} jwtMoved=$jwtMovedCompleted',
    expectedDeny: '42501 completed_at immutable',
    classeNova: true,
    persistedOverride: jwtMovedCompleted,
    title: 'JWT backdate completed_at',
  );

  // B3 disputa ∥ refund race + Δwallet/stock
  final race = await mustPay('DV7', qty: 1);
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
  }, lens: 'DV7');
  denyOrHold(
    id: 'DV-B3.dispute_refund_race',
    matrix: 'DV-B',
    lens: 'DV7',
    payload: 'Future.wait POST disputa ∥ Edge refund-order',
    hit: bothWon ? rfRace : (dRace.status == 201 ? dRace : rfRace),
    bd: 'd=${dRace.status} rf=${rfRace.status} qty $q0→$q1 bothWon=$bothWon st=${raceRow?['status']}',
    expectedDeny:
        'XOR: disputa 201 e refund 403, ou refund 200 e disputa 403; stock +1 no máximo uma vez',
    persistedOverride: bothWon,
    title: 'race disputa∥refund cria dinheiro+stock',
    severity: 'P0',
  );

  // B4 PATCH status disputa/order hostil
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
      id: 'DV-B4.patch_hostile_status',
      matrix: 'DV-B',
      lens: 'DV3',
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
  // DV-C Shipping / label (≥4)
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
  }, lens: 'DV5');
  denyOrHold(
    id: 'DV-C1.patch_ship_after_cs',
    matrix: 'DV-C',
    lens: 'DV5',
    payload: 'após create-payment-intent (cs_) JWT PATCH shipping_method=ctt',
    hit: c1patch,
    bd: 'sid=${c1before?['stripe_checkout_session_id']} ${c1before?['shipping_method']}→${c1after?['shipping_method']} changed=$c1Changed',
    expectedDeny: '42501 frozen ou selo revertido (mão intacto)',
    persistedOverride: c1Changed,
    title: 'selo portes após Session open',
    severity: 'P1',
  );

  // C2 PATCH shipping após pago
  final c2 = await mustPay('DV5', qty: 1);
  final c2b = await c.orderRow(c2.oid);
  final c2p = await c.patchOrder(c2.oid, {'shipping_method': 'ctt'});
  final c2a = await c.orderRow(c2.oid);
  final c2Changed = '${c2a?['shipping_method']}' != '${c2b?['shipping_method']}' &&
      '${c2a?['shipping_method']}'.toLowerCase().contains('ctt');
  denyOrHold(
    id: 'DV-C2.patch_ship_after_pago',
    matrix: 'DV-C',
    lens: 'DV5',
    payload: 'order paga JWT PATCH shipping_method=ctt',
    hit: c2p,
    bd: '${c2b?['shipping_method']}→${c2a?['shipping_method']} paid=${c2a?['amount_paid_cents']}',
    expectedDeny: '42501 order_shipping_frozen_after_payment',
    persistedOverride: c2Changed,
    title: 'selo portes após pago',
    severity: 'P1',
  );

  // C3 bag portes mistos (CTT+mão) amount
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
  }, lens: 'DV5');
  denyOrHold(
    id: 'DV-C3.bag_mixed_shipping',
    matrix: 'DV-C',
    lens: 'DV5',
    payload: 'bag CTT(3,50)+mão; body shipping=mao amount=1',
    hit: mixHit,
    bd: 'amt=$mixAmt cheap=$mixCheap a=$mixOidA b=$mixOidB',
    expectedDeny: 'portes = max selos (≥350¢ CTT) + itens; não cair para mão',
    classeNova: true,
    persistedOverride: mixCheap,
    title: 'saco portes misturados subcotados',
    severity: 'P1',
  );

  // C4 label concat / host evil / @ / https:/
  HttpHit c4at = HttpHit(0, 'no_did', null);
  HttpHit c4hs = HttpHit(0, 'no_did', null);
  Map<String, dynamic>? c4row;
  if (did != null) {
    final atUrl =
        'https://fxdknzrqjenzqcvnwqqq.supabase.co@evil.example/storage/v1/object/sign/fleaber_private/'
        'order_disputes/${c.buyerId}/${hp.oid}/ok.png';
    c4at = await c.patchDispute(did, {'return_label_url': atUrl});
    final hsUrl =
        'https:/fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
        'order_disputes/${c.buyerId}/${hp.oid}/ok.png';
    c4hs = await c.patchDispute(did, {'return_label_url': hsUrl});
    c4row = await c.disputeRow(did);
  }
  final c4AtKept = '${c4row?['return_label_url'] ?? ''}'.contains('evil.example');
  final c4HsKept = '${c4row?['return_label_url'] ?? ''}'.contains('https:/f');
  denyOrHold(
    id: 'DV-C4.label_userinfo_at',
    matrix: 'DV-C',
    lens: 'DV6',
    payload: 'PATCH return_label_url host userinfo @evil.example',
    hit: c4at,
    bd: 'stored=${clip(c4row?['return_label_url'], 140)} atKept=$c4AtKept',
    expectedDeny: '400 label_url_denied',
    classeNova: true,
    persistedOverride: c4at.ok && c4AtKept,
    title: 'label host @evil',
  );
  denyOrHold(
    id: 'DV-C4b.label_https_single_slash',
    matrix: 'DV-C',
    lens: 'DV6',
    payload: 'PATCH return_label_url scheme https:/ (um slash)',
    hit: c4hs,
    bd: 'stored=${clip(c4row?['return_label_url'], 140)} hsKept=$c4HsKept',
    expectedDeny: '400 label_url_denied',
    classeNova: true,
    persistedOverride: c4hs.ok && c4HsKept,
    title: 'label https:/ scheme-relative',
  );

  // ===========================================================================
  // DV-D2 refund stock +1 idempotente
  // ===========================================================================
  final rfExtra = await mustPay('DV7', qty: 1);
  final qPre = numOf((await c.productRow(rfExtra.pid))?['quantity'])?.round();
  final rfH = await c.refund(rfExtra.oid);
  final rfH2 = await c.refund(rfExtra.oid);
  final qPost = numOf((await c.productRow(rfExtra.pid))?['quantity'])?.round();
  final st = (await c.orderRow(rfExtra.oid))?['status'];
  final rfId = (await c.orderRow(rfExtra.oid))?['stripe_refund_id'];
  final stockOk = qPost != null && qPre != null && qPost == qPre + 1;
  final doubleStock = qPost != null && qPre != null && qPost > qPre + 1;
  c.note('D2.refund', 'refund idempotente + stock', {
    'rf1': rfH.brief,
    'rf2': rfH2.brief,
    'qty': '$qPre→$qPost',
    'status': st,
    'refund_id': rfId,
  }, lens: 'DV7');
  denyOrHold(
    id: 'DV-D2.refund_stock_idempotent',
    matrix: 'DV-D',
    lens: 'DV7',
    payload: 'refund-order ×2 em pago + stock oracle',
    hit: rfH,
    bd: 'qty $qPre→$qPost status=$st rf=${rfH.status}/${rfH2.status} id=$rfId double=$doubleStock',
    expectedDeny: 'stock +1 uma vez; 2.º refund 4xx/idempotente',
    persistedOverride: doubleStock || (!stockOk && rfH.ok && !isDenied(rfH)),
    title: 'refund duplica stock',
    severity: 'P0',
  );
  passHappy(
    id: 'DV-D2b.refund_happened',
    matrix: 'DV-D',
    lens: 'DV7',
    payload: 'refund-order em pago (caixa: stock +1)',
    hit: rfH,
    bd: 'qty $qPre→$qPost status=$st',
    ok: stockOk || isDenied(rfH),
    title: 'refund stock oráculo',
  );

  await c.dumpAll('pass1.json');
  stdout.writeln(
      'DONE probes=${c.probes.length} findings=${c.findings.length} lenses=${c.lensesHit.toList()..sort()}');
}
