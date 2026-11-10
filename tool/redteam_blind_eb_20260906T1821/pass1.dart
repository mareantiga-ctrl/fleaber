/// RED TEAM CEGO EB — storage / disputa / label / revoke pós-DTDY.
/// Staging only. Não corrige. Matriz A≥6 B≥4 C≥3 D≥3 · ≥4 classe_nova · quota ≥16.
import 'dart:convert';
import 'dart:io';
import '_rteb.dart';

const pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

const jsPolyglot = '''
PNG
<script>alert(1)</script>
console.log('rteb')
''';

const htmlPolyglot = '''
<!DOCTYPE html><html><body><script>alert(1)</script></body></html>
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
      raw.contains('rls') ||
      raw.contains('permission denied') ||
      raw.contains('pgrst') && raw.contains('permission');
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
  final c = Rteb.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.well('EB-A');
  c.well('EB-B');
  c.well('EB-C');
  c.well('EB-D');

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

  final hp = await mustPay('EB7', qty: 1);
  if (!await c.toEnviado(hp.oid)) throw StateError('enviado hp');
  if (!await c.toConcluido(hp.oid)) throw StateError('concluido hp');

  final minePath = c.disputeObj(c.buyerId!, hp.oid, 'ok.png');
  final up = await c.storageUpload(
    objectName: minePath,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final signed = await c.signObject(minePath, jwt: c.buyerJwt);
  c.note('EB1.upload', 'PNG próprio assinado', {
    'up': up.brief,
    'signed': signed,
    'path': minePath,
  }, lens: 'EB1');

  final alienOid = '00000000-0000-0000-0000-00000000eb02';
  final alienKey =
      'order_disputes/${c.buyer2Id}/$alienOid/rteb-secret.png';
  final alienUp = await c.storageUpload(
    objectName: alienKey,
    bytes: pngBytes,
    jwt: c.buyer2Jwt,
  );
  c.note('EB1.alien', 'objecto B2', alienUp.brief, lens: 'EB1');

  String ownSign(String file) =>
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/${c.buyerId}/${hp.oid}/$file';
  final signedOrOwn = signed ?? ownSign('ok.png');

  // ===========================================================================
  // EB-A Storage / path / revoke (≥6)
  // ===========================================================================

  // A1 upload ../ outro buyer
  final a1Name =
      'order_disputes/${c.buyerId}/../${c.buyer2Id}/rteb-dotdot.png';
  final a1Up = await c.storageUpload(
    objectName: a1Name,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final a1GetAlien = await c.storageGet(
    'order_disputes/${c.buyer2Id}/rteb-dotdot.png',
    jwt: c.buyerJwt,
  );
  final a1Loot = a1Up.ok &&
      !isDenied(a1GetAlien) &&
      (a1GetAlien.body.contains('PNG') || a1GetAlien.status == 200);
  denyOrHold(
    id: 'EB-A1.path_dotdot_upload',
    matrix: 'EB-A',
    lens: 'EB1',
    payload: 'POST object order_disputes/{B1}/../{B2}/rteb-dotdot.png',
    hit: a1Loot ? a1GetAlien : a1Up,
    bd: 'up=${a1Up.status} getAlien=${a1GetAlien.status} loot=$a1Loot',
    expectedDeny: '403 RLS / sem GET no prefixo B2',
    persistedOverride: a1Loot,
    title: 'traversal ../ no storage',
  );

  // A2 %2e%2e%2f encoded traversal (classe_nova — não o U+FF0F do DV)
  final a2Name =
      'order_disputes/${c.buyerId}/%2e%2e%2f${c.buyer2Id}/rteb-enc.png';
  final a2Up = await c.storageUpload(
    objectName: a2Name,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final a2Get = await c.storageGet(
    'order_disputes/${c.buyer2Id}/rteb-enc.png',
    jwt: c.buyerJwt,
  );
  final a2Loot = a2Up.ok && a2Get.ok && !isDenied(a2Get);
  denyOrHold(
    id: 'EB-A2.pct_2e2e2f',
    matrix: 'EB-A',
    lens: 'EB1',
    payload: 'POST object …/{B1}/%2e%2e%2f{B2}/rteb-enc.png',
    hit: a2Loot ? a2Get : a2Up,
    bd: 'up=${a2Up.status} get=${a2Get.status} loot=$a2Loot body=${clip(a2Up.body, 80)}',
    expectedDeny: '400 InvalidKey / 403 RLS / sem loot B2',
    classeNova: true,
    persistedOverride: a2Loot,
    title: 'traversal %2e%2e%2f',
    severity: 'P1',
  );

  // A2b overlong UTF-8 slash %c0%af (classe_nova)
  final a2bName =
      'order_disputes/${c.buyerId}/%c0%af%c0%af/${c.buyer2Id}/overlong.png';
  final a2bUp = await c.storageUpload(
    objectName: a2bName,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final a2bGet = await c.storageGet(
    'order_disputes/${c.buyer2Id}/overlong.png',
    jwt: c.buyerJwt,
  );
  final a2bLoot = a2bUp.ok && a2bGet.ok && !isDenied(a2bGet);
  denyOrHold(
    id: 'EB-A2b.overlong_c0af',
    matrix: 'EB-A',
    lens: 'EB1',
    payload: 'POST object …/{B1}/%c0%af%c0%af/{B2}/overlong.png',
    hit: a2bLoot ? a2bGet : a2bUp,
    bd: 'up=${a2bUp.status} get=${a2bGet.status} loot=$a2bLoot',
    expectedDeny: '400 InvalidKey / 403',
    classeNova: true,
    persistedOverride: a2bLoot,
    title: 'overlong UTF-8 slash %c0%af',
    severity: 'P1',
  );

  // A2c unicode slash NOVO U+2044 FRACTION SLASH (não U+FF0F)
  const frac = '\u2044';
  final a2cUrl =
      '$signedOrOwn${frac}order_disputes/${c.buyer2Id}/$alienOid/rteb-secret.png';
  final a2cOk = await proofOkRpc(a2cUrl, c.buyerId!, hp.oid);
  denyOrHold(
    id: 'EB-A2c.unicode_2044',
    matrix: 'EB-A',
    lens: 'EB1',
    payload: 'proof URL signed + U+2044 FRACTION SLASH + path B2',
    hit: a2cOk,
    bd: 'rpc=${a2cOk.body}',
    expectedDeny: 'proof_ok false',
    classeNova: true,
    persistedOverride: rpcTrue(a2cOk),
    title: 'unicode slash U+2044 na prova',
  );

  // A3 signed URL buyer2 em disputa buyer1
  final a3Signed = await c.signObject(alienKey, jwt: c.buyer2Jwt);
  final a3Url = a3Signed ??
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$alienKey';
  final a3Ok = await proofOkRpc(a3Url, c.buyerId!, hp.oid);
  final a3Get = await c.storageGet(alienKey, jwt: c.buyerJwt);
  denyOrHold(
    id: 'EB-A3.signed_url_buyer2',
    matrix: 'EB-A',
    lens: 'EB6',
    payload: 'RPC proof_ok URL signed B2 em disputa B1 + GET objecto B2 como B1',
    hit: a3Ok,
    bd: 'rpc=${a3Ok.body} getB2asB1=${a3Get.brief}',
    expectedDeny: 'rpc false + GET NoSuchKey/403',
    persistedOverride: rpcTrue(a3Ok) || (a3Get.ok && !isDenied(a3Get)),
    title: 'URL prova outro buyer',
  );

  // A4 DELETE + revoke RPC + proof_ok false (reteste DTDY — 1 linha anti-atrofia)
  final a4Path = c.disputeObj(c.buyerId!, hp.oid, 'revoke.png');
  final a4Up = await c.storageUpload(
    objectName: a4Path,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final a4Signed = await c.signObject(a4Path, jwt: c.buyerJwt);
  final a4Del = await c.storageDelete(a4Path, jwt: c.buyerJwt);
  final a4AuthAfter = await c.storageGet(a4Path, jwt: c.buyerJwt);
  final a4Rev = await c.revokePath(a4Path, jwt: c.buyerJwt);
  final a4ProofUrl = a4Signed ?? ownSign('revoke.png');
  final a4Canon =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$a4Path';
  final a4OkAfter = await proofOkRpc(a4Canon, c.buyerId!, hp.oid);
  final a4AuthGone = isDenied(a4AuthAfter) || a4AuthAfter.status == 404;
  final a4ProofStillTrue = rpcTrue(a4OkAfter);
  c.note('A4.revoke', 'DELETE + revoke RPC + proof_ok', {
    'up': a4Up.brief,
    'del': a4Del.brief,
    'authAfter': a4AuthAfter.brief,
    'rev': a4Rev.brief,
    'proof_ok': a4OkAfter.body,
    'canon': a4Canon,
  }, lens: 'EB2');

  // A5 JWT INSERT/SELECT registry (reteste DV P1 / DTDY)
  final a5AlienPath =
      'order_disputes/${c.buyer2Id}/${hp.oid}/hostile-revoke.png';
  final a5Ins = await c.revokedInsert(a5AlienPath, jwt: c.buyerJwt);
  final a5Sel = await c.revokedSelect(jwt: c.buyerJwt);
  final a5Wrote = a5Ins.ok && !isDenied(a5Ins) && !emptyOk(a5Ins);
  final a5Leak = a5Sel.ok &&
      !isDenied(a5Sel) &&
      a5Sel.list.isNotEmpty &&
      a5Sel.list.any((e) =>
          e is Map && '${e['object_path']}'.contains('${c.buyer2Id}'));
  c.note('A5.table', 'INSERT/SELECT batata_private_object_revoked', {
    'ins': a5Ins.brief,
    'selJwt': a5Sel.brief,
  }, lens: 'EB2');

  // Combined DTDY retest: INSERT deny + proof_ok false (1 linha residual se ambos OK)
  final dtdyClosed = a4AuthGone && !a4ProofStillTrue && !a5Wrote && !a5Leak;
  denyOrHold(
    id: 'EB-A4A5.dtdy_revoke_retest',
    matrix: 'EB-A',
    lens: 'EB2',
    payload:
        'A4 DELETE+revoke+proof_ok + A5 JWT INSERT/SELECT registry (reteste DTDY)',
    hit: a4ProofStillTrue
        ? a4OkAfter
        : (a5Wrote || a5Leak ? a5Ins : a4OkAfter),
    bd: 'auth=${a4AuthAfter.status} rev=${a4Rev.body} proof_ok=${a4OkAfter.body} ins=${a5Ins.status} sel=${a5Sel.status} n=${a5Sel.list.length} wrote=$a5Wrote leak=$a5Leak',
    expectedDeny: 'auth 404; proof_ok false; INSERT/SELECT 401/403',
    residual: dtdyClosed,
    classeNova: false,
    persistedOverride: !dtdyClosed,
    title: 'DTDY revoke/proof_ok / GRANT JWT',
    severity: a5Wrote || a5Leak ? 'P1' : 'P2',
  );

  // Keep A4 and A5 as explicit matrix rows (same evidence)
  denyOrHold(
    id: 'EB-A4.delete_revoke_proof_ok',
    matrix: 'EB-A',
    lens: 'EB3',
    payload: 'upload → DELETE → auth GET + revoke RPC + proof_ok canónico',
    hit: a4OkAfter,
    bd: 'del=${a4Del.status} authAfter=${a4AuthAfter.status} rev=${a4Rev.body} proof_ok=${a4OkAfter.body}',
    expectedDeny: 'auth GET 404; revoke true; proof_ok false',
    residual: !a4ProofStillTrue && a4AuthGone,
    persistedOverride: !a4AuthGone || a4ProofStillTrue,
    title: 'revoke RPC vs proof_ok',
    severity: 'P2',
  );
  denyOrHold(
    id: 'EB-A5.jwt_insert_select_revoke',
    matrix: 'EB-A',
    lens: 'EB2',
    payload: 'JWT B1 POST+GET batata_private_object_revoked path B2',
    hit: a5Ins,
    bd: 'ins=${a5Ins.brief} sel=${a5Sel.status} n=${a5Sel.list.length} wrote=$a5Wrote leak=$a5Leak',
    expectedDeny: '401/403 GRANT; sem SELECT leak',
    residual: !a5Wrote && !a5Leak,
    persistedOverride: a5Wrote || a5Leak,
    title: 'JWT INSERT/SELECT revoke registry',
    severity: 'P1',
  );

  // A5b GraphQL / PostgREST schema leak (classe_nova)
  final a5gql = await c.req(
    'POST',
    '/graphql/v1',
    jwt: c.buyerJwt,
    body: {
      'query':
          'query { batata_private_object_revokedCollection { edges { node { object_path } } } }',
    },
  );
  final gqlLeak = a5gql.ok &&
      !isDenied(a5gql) &&
      a5gql.body.contains('object_path') &&
      !a5gql.body.contains('errors');
  denyOrHold(
    id: 'EB-A5b.graphql_revoke_collection',
    matrix: 'EB-A',
    lens: 'EB2',
    payload: 'POST /graphql/v1 batata_private_object_revokedCollection',
    hit: a5gql,
    bd: 'gqlLeak=$gqlLeak body=${clip(a5gql.body, 160)}',
    expectedDeny: '401/403 / errors / collection ausente',
    classeNova: true,
    persistedOverride: gqlLeak,
    title: 'GraphQL lê revoke registry',
    severity: 'P1',
  );

  // A6 mime JS / polyglot
  final a6Path = c.disputeObj(c.buyerId!, hp.oid, 'poly.js');
  final a6Up = await c.storageUpload(
    objectName: a6Path,
    bytes: utf8.encode(jsPolyglot),
    jwt: c.buyerJwt,
    contentType: 'application/javascript',
  );
  final a6HtmlPath = c.disputeObj(c.buyerId!, hp.oid, 'poly.html');
  final a6HtmlUp = await c.storageUpload(
    objectName: a6HtmlPath,
    bytes: utf8.encode(htmlPolyglot),
    jwt: c.buyerJwt,
    contentType: 'text/html',
  );
  final a6JsOk = a6Up.ok && !isDenied(a6Up);
  final a6HtmlOk = a6HtmlUp.ok && !isDenied(a6HtmlUp);
  denyOrHold(
    id: 'EB-A6.mime_js_html',
    matrix: 'EB-A',
    lens: 'EB1',
    payload: 'upload poly.js CT=application/javascript + poly.html CT=text/html',
    hit: a6JsOk ? a6Up : a6HtmlUp,
    bd: 'js=${a6Up.status} html=${a6HtmlUp.status} jsOk=$a6JsOk htmlOk=$a6HtmlOk',
    expectedDeny: '415 InvalidMimeType',
    classeNova: true,
    persistedOverride: a6JsOk || a6HtmlOk,
    title: 'mime JS/HTML aceite no private bucket',
  );

  // A6b null byte in path (classe_nova)
  final a6bName =
      'order_disputes/${c.buyerId}/${hp.oid}/ok.png%00.js';
  final a6bUp = await c.storageUpload(
    objectName: a6bName,
    bytes: pngBytes,
    jwt: c.buyerJwt,
    contentType: 'image/png',
  );
  final a6bGetJs = await c.storageGet(
    'order_disputes/${c.buyerId}/${hp.oid}/ok.png',
    jwt: c.buyerJwt,
  );
  final a6bTrunc = a6bUp.ok &&
      !isDenied(a6bUp) &&
      (a6bUp.body.contains('ok.png') && !a6bUp.body.contains('%00'));
  denyOrHold(
    id: 'EB-A6b.null_byte_path',
    matrix: 'EB-A',
    lens: 'EB1',
    payload: 'POST object …/ok.png%00.js',
    hit: a6bTrunc ? a6bUp : (isDenied(a6bUp) ? a6bUp : HttpHit(400, a6bUp.brief, null)),
    bd: 'up=${a6bUp.status} getOkPng=${a6bGetJs.status} trunc=$a6bTrunc body=${clip(a6bUp.body, 80)}',
    expectedDeny: '400 InvalidKey / 415; sem truncate sobre ok.png',
    classeNova: true,
    persistedOverride: a6bTrunc,
    title: 'null byte no path',
  );

  // A6c Windows ..\ (classe_nova)
  final a6cName =
      r'order_disputes/' + '${c.buyerId}/..\\${c.buyer2Id}/win.png';
  final a6cUp = await c.storageUpload(
    objectName: a6cName,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final a6cGet = await c.storageGet(
    'order_disputes/${c.buyer2Id}/win.png',
    jwt: c.buyerJwt,
  );
  final a6cLoot = a6cUp.ok && a6cGet.ok && !isDenied(a6cGet);
  denyOrHold(
    id: 'EB-A6c.windows_backslash',
    matrix: 'EB-A',
    lens: 'EB1',
    payload: r'POST object …/{B1}/..\{B2}/win.png',
    hit: a6cLoot ? a6cGet : a6cUp,
    bd: 'up=${a6cUp.status} get=${a6cGet.status} loot=$a6cLoot',
    expectedDeny: '400 InvalidKey / 403 RLS',
    classeNova: true,
    persistedOverride: a6cLoot,
    title: r'traversal Windows ..\',
    severity: 'P1',
  );

  // A7 encoded-slash bypass of registry (revoke literal / then proof_ok with %2f)
  final a7Path = c.disputeObj(c.buyerId!, hp.oid, 'encslash.png');
  await c.storageUpload(objectName: a7Path, bytes: pngBytes, jwt: c.buyerJwt);
  await c.storageDelete(a7Path, jwt: c.buyerJwt);
  await c.revokePath(a7Path, jwt: c.buyerJwt);
  final a7EncUrl =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/${c.buyerId}%2f${hp.oid}%2fencslash.png';
  final a7Ok = await proofOkRpc(a7EncUrl, c.buyerId!, hp.oid);
  denyOrHold(
    id: 'EB-A7.pct2f_bypass_revoke_registry',
    matrix: 'EB-A',
    lens: 'EB3',
    payload: 'revoke path com / ; proof_ok URL com %2f no mesmo objecto',
    hit: a7Ok,
    bd: 'rpc=${a7Ok.body} path=$a7Path',
    expectedDeny: 'proof_ok false (canónico deve bater no registry)',
    classeNova: true,
    persistedOverride: rpcTrue(a7Ok),
    title: '%2f bypass do registry revoke',
    severity: 'P2',
  );

  // A8 storage MOVE para prefixo B2 (classe_nova)
  final a8Src = c.disputeObj(c.buyerId!, hp.oid, 'move-src.png');
  await c.storageUpload(objectName: a8Src, bytes: pngBytes, jwt: c.buyerJwt);
  final a8Dest =
      'order_disputes/${c.buyer2Id}/$alienOid/moved.png';
  final a8 = await c.storageMove(
    sourceKey: a8Src,
    destKey: a8Dest,
    jwt: c.buyerJwt,
  );
  final a8Get = await c.storageGet(a8Dest, jwt: c.buyerJwt);
  final a8Loot = a8.ok && !isDenied(a8) && a8Get.ok && !isDenied(a8Get);
  denyOrHold(
    id: 'EB-A8.storage_move_alien_prefix',
    matrix: 'EB-A',
    lens: 'EB1',
    payload: 'POST /object/move source=próprio dest=order_disputes/{B2}/…',
    hit: a8,
    bd: 'move=${a8.brief} get=${a8Get.brief} loot=$a8Loot',
    expectedDeny: '403 RLS move/dest',
    classeNova: true,
    persistedOverride: a8Loot,
    title: 'storage MOVE para prefixo alheio',
    severity: 'P1',
  );

  // A9 revoke RPC path traversal (classe_nova)
  final a9Trav =
      'order_disputes/${c.buyerId}/../${c.buyer2Id}/$alienOid/rteb-secret.png';
  final a9 = await c.revokePath(a9Trav, jwt: c.buyerJwt);
  denyOrHold(
    id: 'EB-A9.revoke_rpc_dotdot_alien',
    matrix: 'EB-A',
    lens: 'EB2',
    payload: 'RPC revoke p_path=order_disputes/{B1}/../{B2}/…',
    hit: a9,
    bd: 'rpc=${a9.body}',
    expectedDeny: '42501 revoke_forbidden / false',
    classeNova: true,
    persistedOverride: rpcTrue(a9),
    title: 'revoke RPC traversal path alheio',
    severity: 'P1',
  );

  // ===========================================================================
  // EB-D1 happy disputa (caixa + actor OK) — precisa disputa para C2/C3
  // ===========================================================================
  final d1Ins = await c.insertDispute(orderId: hp.oid, photos: [signedOrOwn]);
  var did = d1Ins.firstId;
  passHappy(
    id: 'EB-D1.pago_proof_feliz',
    matrix: 'EB-D',
    lens: 'EB7',
    payload: 'POST order_disputes proof signed própria em concluido (4242)',
    hit: d1Ins,
    bd: 'id=$did photos=${clip(d1Ins.map?['proof_photos'], 120)} pi=${hp.pi}',
    ok: d1Ins.status == 201 && did != null,
    title: 'disputa+prova signed 201',
  );

  // CTRL anti-atrofia %252f e // (não contar)
  if (did != null) {
    final ctrl252f =
        '${signedOrOwn}%252forder_disputes/${c.buyer2Id}/$alienOid/rteb-secret.png';
    final ctrlHit =
        await c.patchDispute(did, {'return_label_url': ctrl252f});
    final stored = await c.disputeRow(did);
    final persisted252f =
        ctrlHit.ok && '${stored?['return_label_url'] ?? ''}'.contains('%252f');
    denyOrHold(
      id: 'EB-CTRL.label_252f',
      matrix: 'EB-C',
      lens: 'EB5',
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
      id: 'EB-CTRL.slashslash_after_host',
      matrix: 'EB-C',
      lens: 'EB5',
      payload: 'PATCH label signed + //extra.png após ficheiro',
      hit: slashHit,
      bd: 'stored after=${clip((await c.disputeRow(did))?['return_label_url'], 100)}',
      expectedDeny: '400 // após host',
      residual: true,
      title: '// após host residual',
    );
  }

  // A5 signed GET pós-DELETE (CDN residual — máx 1 HOLD se 200)
  HttpHit aCdn = HttpHit(0, 'no_sign', null);
  if (a4Signed != null) {
    aCdn = await c.storageGetSigned(a4Signed);
  }
  final cdn200 = aCdn.ok &&
      !isDenied(aCdn) &&
      (aCdn.body.contains('PNG') || aCdn.status == 200);
  denyOrHold(
    id: 'EB-CTRL.signed_cdn_after_delete',
    matrix: 'EB-A',
    lens: 'EB2',
    payload: 'GET da signed URL após DELETE+revoke (CDN residual)',
    hit: aCdn,
    bd: 'auth=${a4AuthAfter.status} signed=${aCdn.status} cdn200=$cdn200',
    expectedDeny: '404/400; se 200 = residual plataforma (máx 1 HOLD)',
    residual: true,
    persistedOverride: cdn200,
    title: 'signed CDN 200 pós-DELETE',
  );

  // ===========================================================================
  // EB-B Disputa FSM (≥4)
  // ===========================================================================

  // B1 disputa order alheia
  final b1 = await c.insertDispute(
    orderId: hp.oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  denyOrHold(
    id: 'EB-B1.dispute_order_alheia',
    matrix: 'EB-B',
    lens: 'EB6',
    payload: 'B2 POST order_disputes na order paga de B1',
    hit: b1,
    bd: 'oid=${hp.oid} id=${b1.firstId}',
    expectedDeny: '403 RLS / buyer_id mismatch',
    title: 'disputa order alheia',
  );

  // B2 disputa em enviado / pós-release (janela clássica = residual 1 linha)
  final envOnly = await mustPay('EB4', qty: 1);
  if (!await c.toEnviado(envOnly.oid)) throw StateError('env only');
  final b2 = await c.insertDispute(orderId: envOnly.oid);
  denyOrHold(
    id: 'EB-B2.window_enviado',
    matrix: 'EB-B',
    lens: 'EB4',
    payload: 'POST disputa em status=enviado (ainda não concluido)',
    hit: b2,
    bd: 'status=${(await c.orderRow(envOnly.oid))?['status']} id=${b2.firstId}',
    expectedDeny: '403 só concluido/entregue',
    residual: true,
    title: 'disputa na janela enviado',
  );

  final win = await mustPay('EB4', qty: 1);
  if (!await c.toEnviado(win.oid)) throw StateError('env win');
  if (!await c.toConcluido(win.oid)) throw StateError('conc win');
  await c.patchOrder(win.oid, {
    'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String(),
  }, service: true);
  final b2r = await c.insertDispute(orderId: win.oid);
  denyOrHold(
    id: 'EB-B2b.window_after_release',
    matrix: 'EB-B',
    lens: 'EB4',
    payload: 'POST disputa após wallet_release_processed_at',
    hit: b2r,
    bd: 'oid=${win.oid} id=${b2r.firstId}',
    expectedDeny: '403 residual janela clássica',
    residual: true,
    title: 'disputa fora de janela pós-release',
  );

  // B3 disputa ∥ refund race + Δwallet/stock
  final race = await mustPay('EB7', qty: 1);
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
  }, lens: 'EB7');
  denyOrHold(
    id: 'EB-B3.dispute_refund_race',
    matrix: 'EB-B',
    lens: 'EB7',
    payload: 'Future.wait POST disputa ∥ Edge refund-order',
    hit: bothWon ? rfRace : (dRace.status == 201 ? dRace : rfRace),
    bd: 'd=${dRace.status} rf=${rfRace.status} qty $q0→$q1 bothWon=$bothWon st=${raceRow?['status']}',
    expectedDeny:
        'XOR: disputa 201 e refund 403, ou refund 200 e disputa 403; stock +1 no máximo uma vez',
    persistedOverride: bothWon,
    title: 'race disputa∥refund cria dinheiro+stock',
    severity: 'P0',
  );

  // B4 proof URL forjada — path alheio
  final b4AlienOk = await proofOkRpc(a3Url, c.buyerId!, hp.oid);
  HttpHit b4AlienIns = HttpHit(0, 'no_try', null);
  if (rpcTrue(b4AlienOk)) {
    b4AlienIns = await c.insertDispute(
      orderId: hp.oid,
      photos: [a3Url],
    );
  } else {
    b4AlienIns = await c.patchDispute(did ?? '00000000-0000-0000-0000-000000000001', {
      'proof_photos': [a3Url],
    });
  }
  final b4AlienKept = did == null
      ? false
      : '${(await c.disputeRow(did))?['proof_photos']}'.contains('$alienOid');
  denyOrHold(
    id: 'EB-B4.forged_alien_path',
    matrix: 'EB-B',
    lens: 'EB3',
    payload: 'proof_ok + persist URL signed B2 na disputa B1',
    hit: b4AlienOk,
    bd: 'rpc=${b4AlienOk.body} persist=${b4AlienIns.brief} kept=$b4AlienKept',
    expectedDeny: 'proof_ok false; persist 400/200[]',
    classeNova: true,
    persistedOverride: rpcTrue(b4AlienOk) || b4AlienKept,
    title: 'prova path alheio forjada',
    severity: 'P1',
  );

  // B4b object revogado (URL antiga signed)
  final b4bOk = await proofOkRpc(a4ProofUrl, c.buyerId!, hp.oid);
  HttpHit b4bPatch = HttpHit(0, 'no_did', null);
  bool b4bKept = false;
  if (did != null) {
    b4bPatch = await c.patchDispute(did, {
      'proof_photos': [a4ProofUrl],
    });
    b4bKept = '${(await c.disputeRow(did))?['proof_photos']}'.contains('revoke.png');
  }
  denyOrHold(
    id: 'EB-B4b.forged_revoked_old_url',
    matrix: 'EB-B',
    lens: 'EB3',
    payload: 'proof_ok + PATCH photos URL signed antiga de objecto revogado',
    hit: b4bOk,
    bd: 'rpc=${b4bOk.body} patch=${b4bPatch.brief} kept=$b4bKept',
    expectedDeny: 'proof_ok false; persist denied',
    classeNova: true,
    persistedOverride: rpcTrue(b4bOk) || b4bKept,
    title: 'prova URL antiga de objecto revogado',
    severity: 'P2',
  );

  // ===========================================================================
  // EB-C Shipping / label (≥3)
  // ===========================================================================

  // C1 PATCH portes após cs_ open / pago
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

  final c2pay = await mustPay('EB5', qty: 1);
  final c2b = await c.orderRow(c2pay.oid);
  final c2p = await c.patchOrder(c2pay.oid, {'shipping_method': 'ctt'});
  final c2a = await c.orderRow(c2pay.oid);
  final c2Changed = '${c2a?['shipping_method']}' != '${c2b?['shipping_method']}' &&
      '${c2a?['shipping_method']}'.toLowerCase().contains('ctt');
  denyOrHold(
    id: 'EB-C1.patch_ship_after_cs_pago',
    matrix: 'EB-C',
    lens: 'EB5',
    payload: 'PATCH shipping=ctt após Session e após pago',
    hit: c1Changed ? c1patch : c2p,
    bd: 'cs=${c1cs.status} ${c1before?['shipping_method']}→${c1after?['shipping_method']} paid ${c2b?['shipping_method']}→${c2a?['shipping_method']} c1=$c1Changed c2=$c2Changed paid=${c2a?['amount_paid_cents']}',
    expectedDeny: 'selo mão intacto; 200[] / 42501',
    persistedOverride: c1Changed || c2Changed,
    title: 'selo portes após cs_/pago',
    severity: 'P1',
  );

  // C2 label path traversal + forge order_id (classe_nova)
  HttpHit c2lab = HttpHit(0, 'no_did', null);
  Map<String, dynamic>? c2labRow;
  final fakeOid = '11111111-1111-1111-1111-111111111111';
  final travLabel =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/${c.buyerId}/../$fakeOid/ok.png';
  if (did != null) {
    c2lab = await c.patchDispute(did, {'return_label_url': travLabel});
    c2labRow = await c.disputeRow(did);
  }
  final c2labKept = '${c2labRow?['return_label_url'] ?? ''}'.contains(fakeOid) ||
      '${c2labRow?['return_label_url'] ?? ''}'.contains('../');
  denyOrHold(
    id: 'EB-C2.label_traversal_forge_oid',
    matrix: 'EB-C',
    lens: 'EB5',
    payload: 'PATCH return_label_url …/{B1}/../{fakeOid}/ok.png',
    hit: c2lab,
    bd: 'stored=${clip(c2labRow?['return_label_url'], 160)} kept=$c2labKept',
    expectedDeny: '400 label_url_denied / 200[]',
    classeNova: true,
    persistedOverride: c2lab.ok && c2labKept,
    title: 'label traversal + order_id forjado',
    severity: 'P1',
  );

  // C2b forge order_id in own prefix (same buyer, other oid)
  HttpHit c2bLab = HttpHit(0, 'no_did', null);
  final otherOidLabel =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/${c.buyerId}/$fakeOid/ok.png';
  Map<String, dynamic>? c2bRow;
  if (did != null) {
    c2bLab = await c.patchDispute(did, {'return_label_url': otherOidLabel});
    c2bRow = await c.disputeRow(did);
  }
  final c2bKept = '${c2bRow?['return_label_url'] ?? ''}'.contains(fakeOid);
  denyOrHold(
    id: 'EB-C2b.label_forge_order_id',
    matrix: 'EB-C',
    lens: 'EB5',
    payload: 'PATCH label path order_disputes/{B1}/{oid_forjado}/ok.png',
    hit: c2bLab,
    bd: 'stored=${clip(c2bRow?['return_label_url'], 140)} kept=$c2bKept',
    expectedDeny: '400 label deve coincidir com order_id da disputa',
    classeNova: true,
    persistedOverride: c2bLab.ok && c2bKept,
    title: 'label order_id forjado no prefixo próprio',
  );

  // C3 seller2 lê label buyer1 (classe_nova)
  // Plant a valid-looking label on own object first if possible.
  final labelPath = c.disputeObj(c.buyerId!, hp.oid, 'label.png');
  await c.storageUpload(
    objectName: labelPath,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final labelSigned = await c.signObject(labelPath, jwt: c.buyerJwt);
  if (did != null && labelSigned != null) {
    await c.patchDispute(did, {'return_label_url': labelSigned});
  }
  final c3RowS2 = await c.rest(
    'GET',
    'order_disputes?id=eq.${did ?? '00000000-0000-0000-0000-000000000001'}&select=id,return_label_url,proof_photos,buyer_id,order_id',
    jwt: c.seller2Jwt,
  );
  final c3GetObj = await c.storageGet(labelPath, jwt: c.seller2Jwt);
  final c3List = await c.storageList(
    prefix: 'order_disputes/${c.buyerId}/',
    jwt: c.seller2Jwt,
  );
  final c3LeakRow = c3RowS2.ok &&
      !isDenied(c3RowS2) &&
      !emptyOk(c3RowS2) &&
      (c3RowS2.map?['return_label_url'] != null ||
          (c3RowS2.list.isNotEmpty));
  final c3LootObj = c3GetObj.ok && !isDenied(c3GetObj);
  final c3ListLeak = c3List.ok &&
      !isDenied(c3List) &&
      c3List.list.isNotEmpty;
  denyOrHold(
    id: 'EB-C3.seller2_reads_label_buyer1',
    matrix: 'EB-C',
    lens: 'EB6',
    payload: 'S2 GET order_disputes id B1 + GET/LIST storage label B1',
    hit: c3LeakRow ? c3RowS2 : (c3LootObj ? c3GetObj : c3List),
    bd: 'rowS2=${c3RowS2.status} n=${c3RowS2.list.length} getObj=${c3GetObj.status} list=${c3List.status} leakRow=$c3LeakRow lootObj=$c3LootObj listLeak=$c3ListLeak',
    expectedDeny: '403/[] RLS; storage NoSuchKey',
    classeNova: true,
    persistedOverride: c3LeakRow || c3LootObj || c3ListLeak,
    title: 'seller2 lê label/prova de buyer1',
    severity: 'P1',
  );

  // ===========================================================================
  // EB-D Caixa (≥3) — D2 revoke mid-disputa; D3 re-upload mesmo path
  // ===========================================================================

  // D2: disputa aberta → revoke objecto da prova → proof_ok + PATCH
  final d2pay = await mustPay('EB7', qty: 1);
  if (!await c.toEnviado(d2pay.oid)) throw StateError('env d2');
  if (!await c.toConcluido(d2pay.oid)) throw StateError('conc d2');
  final d2Path = c.disputeObj(c.buyerId!, d2pay.oid, 'mid.png');
  await c.storageUpload(objectName: d2Path, bytes: pngBytes, jwt: c.buyerJwt);
  final d2Signed = await c.signObject(d2Path, jwt: c.buyerJwt);
  final d2Url = d2Signed ??
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$d2Path';
  final d2Ins = await c.insertDispute(orderId: d2pay.oid, photos: [d2Url]);
  final d2did = d2Ins.firstId;
  await c.storageDelete(d2Path, jwt: c.buyerJwt);
  final d2Rev = await c.revokePath(d2Path, jwt: c.buyerJwt);
  final d2Canon =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$d2Path';
  final d2Ok = await proofOkRpc(d2Canon, c.buyerId!, d2pay.oid);
  HttpHit d2Patch = HttpHit(0, 'no_did', null);
  bool d2KeptNew = false;
  if (d2did != null) {
    d2Patch = await c.patchDispute(d2did, {
      'proof_photos': [d2Canon],
    });
    d2KeptNew =
        '${(await c.disputeRow(d2did))?['proof_photos']}'.contains('mid.png');
  }
  final d2RowAfter = d2did == null ? null : await c.disputeRow(d2did);
  c.note('D2.mid', 'revoke mid-disputa', {
    'ins': d2Ins.brief,
    'rev': d2Rev.body,
    'proof_ok': d2Ok.body,
    'patch': d2Patch.brief,
    'photos': d2RowAfter?['proof_photos'],
  }, lens: 'EB3');
  denyOrHold(
    id: 'EB-D2.revoke_mid_dispute_proof_ok',
    matrix: 'EB-D',
    lens: 'EB3',
    payload: 'disputa 201 → DELETE+revoke prova → proof_ok + PATCH photos',
    hit: d2Ok,
    bd: 'ins=${d2Ins.status} did=$d2did rev=${d2Rev.body} proof_ok=${d2Ok.body} patch=${d2Patch.status} kept=$d2KeptNew',
    expectedDeny: 'proof_ok false; PATCH 400/200[] (row existente pode manter URL antiga)',
    classeNova: true,
    persistedOverride: rpcTrue(d2Ok),
    title: 'proof_ok true após revoke a meio da disputa',
    severity: 'P2',
  );

  // D3 re-upload mesmo path após revoke
  final d3Path = c.disputeObj(c.buyerId!, d2pay.oid, 'reup.png');
  await c.storageUpload(objectName: d3Path, bytes: pngBytes, jwt: c.buyerJwt);
  final d3SignedOld = await c.signObject(d3Path, jwt: c.buyerJwt);
  await c.storageDelete(d3Path, jwt: c.buyerJwt);
  await c.revokePath(d3Path, jwt: c.buyerJwt);
  final d3Re = await c.storageUpload(
    objectName: d3Path,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final d3Canon =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$d3Path';
  final d3OkAfterRe = await proofOkRpc(d3Canon, c.buyerId!, d2pay.oid);
  HttpHit d3OldGet = HttpHit(0, 'no_old', null);
  if (d3SignedOld != null) {
    d3OldGet = await c.storageGetSigned(d3SignedOld);
  }
  final d3Auth = await c.storageGet(d3Path, jwt: c.buyerJwt);
  c.note('D3.reup', 're-upload após revoke', {
    're': d3Re.brief,
    'proof_ok': d3OkAfterRe.body,
    'oldSigned': d3OldGet.brief,
    'auth': d3Auth.brief,
  }, lens: 'EB2');
  // Finding if: re-upload 200 AND proof_ok true using the OLD signed URL
  // (confused deputy / revoke wiped by upsert), OR proof_ok true on canon
  // without a new sign after sticky-revoke was expected.
  // Security intent DTDY: registry is sticky by path → proof_ok should stay false
  // even after re-upload. If true, revoke is ephemeral (P2 hygiene).
  denyOrHold(
    id: 'EB-D3.reupload_same_path_after_revoke',
    matrix: 'EB-D',
    lens: 'EB2',
    payload: 'DELETE+revoke path → POST mesmo path → proof_ok canónico + GET signed antiga',
    hit: d3OkAfterRe,
    bd: 're=${d3Re.status} proof_ok=${d3OkAfterRe.body} oldGet=${d3OldGet.status} auth=${d3Auth.status}',
    expectedDeny: 'proof_ok false (registry sticky por path) mesmo após re-upload',
    classeNova: true,
    persistedOverride: rpcTrue(d3OkAfterRe),
    title: 're-upload apaga efeito do revoke no proof_ok',
    severity: 'P2',
  );

  await c.dumpAll('pass1.json');
  stdout.writeln(
      'DONE probes=${c.probes.length} findings=${c.findings.length} lenses=${c.lensesHit.toList()..sort()}');
}
