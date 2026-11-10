/// RED TEAM CEGO EQ — disputa / storage / portes / label / revoke POS_OPEN_GATE.
/// Staging only. Não corrige. Matriz A≥8 B≥5 C≥5 D≥4 E≥2 · ≥6 classe_nova · quota ≥24.
import 'dart:convert';
import 'dart:io';
import '_rteq.dart';

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
console.log('rteq')
''';

const htmlPolyglot = '''
<!DOCTYPE html><html><body><script>alert(1)</script></body></html>
''';

const svgPolyglot = '''
<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg">
<script>alert(1)</script></svg>
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
      (raw.contains('pgrst') && raw.contains('permission'));
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
  final c = Rteq.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.well('EQ-A');
  c.well('EQ-B');
  c.well('EQ-C');
  c.well('EQ-D');
  c.well('EQ-E');

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

  // ≥2 orders pagas no fio: happy (hp) + 2.º feliz (e1) + races.
  final hp = await mustPay('EQ8', qty: 1);
  if (!await c.toEnviado(hp.oid)) throw StateError('enviado hp');
  if (!await c.toConcluido(hp.oid)) throw StateError('concluido hp');

  final minePath = c.disputeObj(c.buyerId!, hp.oid, 'ok.png');
  final up = await c.storageUpload(
    objectName: minePath,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final signed = await c.signObject(minePath, jwt: c.buyerJwt);
  c.note('EQ1.upload', 'PNG próprio assinado', {
    'up': up.brief,
    'signed': signed,
    'path': minePath,
  }, lens: 'EQ1');

  final alienOid = '00000000-0000-0000-0000-00000000eq02';
  final alienKey = 'order_disputes/${c.buyer2Id}/$alienOid/rteq-secret.png';
  final alienUp = await c.storageUpload(
    objectName: alienKey,
    bytes: pngBytes,
    jwt: c.buyer2Jwt,
  );
  c.note('EQ1.alien', 'objecto B2', alienUp.brief, lens: 'EQ1');

  String ownSign(String file) =>
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/${c.buyerId}/${hp.oid}/$file';
  final signedOrOwn = signed ?? ownSign('ok.png');

  // ===========================================================================
  // EQ-A Storage / path (≥8)
  // ===========================================================================

  // A1 upload ../ outro buyer
  final a1Name =
      'order_disputes/${c.buyerId}/../${c.buyer2Id}/rteq-dotdot.png';
  final a1Up = await c.storageUpload(
    objectName: a1Name,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final a1GetAlien = await c.storageGet(
    'order_disputes/${c.buyer2Id}/rteq-dotdot.png',
    jwt: c.buyerJwt,
  );
  final a1Loot = a1Up.ok &&
      !isDenied(a1GetAlien) &&
      (a1GetAlien.body.contains('PNG') || a1GetAlien.status == 200);
  denyOrHold(
    id: 'EQ-A1.path_dotdot_upload',
    matrix: 'EQ-A',
    lens: 'EQ1',
    payload: 'POST object order_disputes/{B1}/../{B2}/rteq-dotdot.png',
    hit: a1Loot ? a1GetAlien : a1Up,
    bd: 'up=${a1Up.status} getAlien=${a1GetAlien.status} loot=$a1Loot',
    expectedDeny: '403 RLS / sem GET no prefixo B2',
    persistedOverride: a1Loot,
    title: 'traversal ../ no storage',
    severity: 'P1',
  );

  // A2 %2e%2e%2f
  final a2Name =
      'order_disputes/${c.buyerId}/%2e%2e%2f${c.buyer2Id}/rteq-enc.png';
  final a2Up = await c.storageUpload(
    objectName: a2Name,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final a2Get = await c.storageGet(
    'order_disputes/${c.buyer2Id}/rteq-enc.png',
    jwt: c.buyerJwt,
  );
  final a2Loot = a2Up.ok && a2Get.ok && !isDenied(a2Get);
  denyOrHold(
    id: 'EQ-A2.pct_2e2e2f',
    matrix: 'EQ-A',
    lens: 'EQ1',
    payload: 'POST object …/{B1}/%2e%2e%2f{B2}/rteq-enc.png',
    hit: a2Loot ? a2Get : a2Up,
    bd: 'up=${a2Up.status} get=${a2Get.status} loot=$a2Loot body=${clip(a2Up.body, 80)}',
    expectedDeny: '400 InvalidKey / 403 RLS / sem loot B2',
    persistedOverride: a2Loot,
    title: 'traversal %2e%2e%2f',
    severity: 'P1',
  );

  // A2b U+FF0F FULLWIDTH SOLIDUS (classe_nova — EB usou U+2044, DQ U+2AFB)
  const fwSlash = '\uFF0F';
  final a2bUrl =
      '$signedOrOwn${fwSlash}order_disputes/${c.buyer2Id}/$alienOid/rteq-secret.png';
  final a2bOk = await proofOkRpc(a2bUrl, c.buyerId!, hp.oid);
  denyOrHold(
    id: 'EQ-A2b.unicode_ff0f',
    matrix: 'EQ-A',
    lens: 'EQ1',
    payload: 'proof URL signed + U+FF0F FULLWIDTH SOLIDUS + path B2 (sem query)',
    hit: a2bOk,
    bd: 'rpc=${a2bOk.body}',
    expectedDeny: 'proof_ok false',
    classeNova: true,
    persistedOverride: rpcTrue(a2bOk),
    title: 'unicode slash U+FF0F na prova',
    severity: 'P1',
  );

  // A2c U+29F8 BIG SOLIDUS (classe_nova)
  const bigSlash = '\u29F8';
  final a2cUrl =
      '$signedOrOwn${bigSlash}order_disputes/${c.buyer2Id}/$alienOid/rteq-secret.png';
  final a2cOk = await proofOkRpc(a2cUrl, c.buyerId!, hp.oid);
  denyOrHold(
    id: 'EQ-A2c.unicode_29f8',
    matrix: 'EQ-A',
    lens: 'EQ1',
    payload: 'proof URL signed + U+29F8 BIG SOLIDUS + path B2 (sem query)',
    hit: a2cOk,
    bd: 'rpc=${a2cOk.body}',
    expectedDeny: 'proof_ok false',
    classeNova: true,
    persistedOverride: rpcTrue(a2cOk),
    title: 'unicode slash U+29F8 na prova',
    severity: 'P1',
  );

  // A2d mixed .%2e / %2e. (classe_nova)
  final a2dName =
      'order_disputes/${c.buyerId}/.%2e/%2e./${c.buyer2Id}/rteq-mix.png';
  final a2dUp = await c.storageUpload(
    objectName: a2dName,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final a2dGet = await c.storageGet(
    'order_disputes/${c.buyer2Id}/rteq-mix.png',
    jwt: c.buyerJwt,
  );
  final a2dLoot = a2dUp.ok && a2dGet.ok && !isDenied(a2dGet);
  denyOrHold(
    id: 'EQ-A2d.mixed_dot_pct2e',
    matrix: 'EQ-A',
    lens: 'EQ1',
    payload: r'POST …/{B1}/.%2e/%2e./{B2}/rteq-mix.png',
    hit: a2dLoot ? a2dGet : a2dUp,
    bd: 'up=${a2dUp.status} get=${a2dGet.status} loot=$a2dLoot',
    expectedDeny: '400/403; sem loot B2',
    classeNova: true,
    persistedOverride: a2dLoot,
    title: 'traversal misto .%2e/%2e.',
    severity: 'P1',
  );

  // A2e double-encoding %252e%252e%252f (classe_nova vs label %252f)
  final a2eName =
      'order_disputes/${c.buyerId}/%252e%252e%252f${c.buyer2Id}/rteq-dbl.png';
  final a2eUp = await c.storageUpload(
    objectName: a2eName,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final a2eGet = await c.storageGet(
    'order_disputes/${c.buyer2Id}/rteq-dbl.png',
    jwt: c.buyerJwt,
  );
  final a2eLoot = a2eUp.ok && a2eGet.ok && !isDenied(a2eGet);
  denyOrHold(
    id: 'EQ-A2e.double_pct252e',
    matrix: 'EQ-A',
    lens: 'EQ1',
    payload: 'POST …/{B1}/%252e%252e%252f{B2}/rteq-dbl.png',
    hit: a2eLoot ? a2eGet : a2eUp,
    bd: 'up=${a2eUp.status} get=${a2eGet.status} loot=$a2eLoot',
    expectedDeny: '400/403; sem loot B2',
    classeNova: true,
    persistedOverride: a2eLoot,
    title: 'double-encoding %252e%252e%252f storage',
    severity: 'P1',
  );

  // A3 Windows ..\
  final a3Name = r'order_disputes/' + '${c.buyerId}/..\\${c.buyer2Id}/win.png';
  final a3Up = await c.storageUpload(
    objectName: a3Name,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final a3Get = await c.storageGet(
    'order_disputes/${c.buyer2Id}/win.png',
    jwt: c.buyerJwt,
  );
  final a3Loot = a3Up.ok && a3Get.ok && !isDenied(a3Get);
  denyOrHold(
    id: 'EQ-A3.windows_backslash',
    matrix: 'EQ-A',
    lens: 'EQ1',
    payload: r'POST object …/{B1}/..\{B2}/win.png',
    hit: a3Loot ? a3Get : a3Up,
    bd: 'up=${a3Up.status} get=${a3Get.status} loot=$a3Loot',
    expectedDeny: '400 InvalidKey / 403 RLS',
    classeNova: true,
    persistedOverride: a3Loot,
    title: r'traversal Windows ..\',
    severity: 'P1',
  );

  // A3b null byte
  final a3bName = 'order_disputes/${c.buyerId}/${hp.oid}/ok.png%00.js';
  final a3bUp = await c.storageUpload(
    objectName: a3bName,
    bytes: pngBytes,
    jwt: c.buyerJwt,
    contentType: 'image/png',
  );
  final a3bTrunc = a3bUp.ok &&
      !isDenied(a3bUp) &&
      (a3bUp.body.contains('ok.png') && !a3bUp.body.contains('%00'));
  denyOrHold(
    id: 'EQ-A3b.null_byte_path',
    matrix: 'EQ-A',
    lens: 'EQ1',
    payload: 'POST object …/ok.png%00.js',
    hit: a3bTrunc ? a3bUp : a3bUp,
    bd: 'up=${a3bUp.status} trunc=$a3bTrunc body=${clip(a3bUp.body, 80)}',
    expectedDeny: '400 InvalidKey / 415; sem truncate',
    classeNova: true,
    persistedOverride: a3bTrunc,
    title: 'null byte no path',
  );

  // A4 mime JS/HTML/SVG — SVG é classe_nova vs EB JS/HTML
  final a4Js = await c.storageUpload(
    objectName: c.disputeObj(c.buyerId!, hp.oid, 'poly.js'),
    bytes: utf8.encode(jsPolyglot),
    jwt: c.buyerJwt,
    contentType: 'application/javascript',
  );
  final a4Html = await c.storageUpload(
    objectName: c.disputeObj(c.buyerId!, hp.oid, 'poly.html'),
    bytes: utf8.encode(htmlPolyglot),
    jwt: c.buyerJwt,
    contentType: 'text/html',
  );
  final a4Svg = await c.storageUpload(
    objectName: c.disputeObj(c.buyerId!, hp.oid, 'poly.svg'),
    bytes: utf8.encode(svgPolyglot),
    jwt: c.buyerJwt,
    contentType: 'image/svg+xml',
  );
  final a4Any = (a4Js.ok && !isDenied(a4Js)) ||
      (a4Html.ok && !isDenied(a4Html)) ||
      (a4Svg.ok && !isDenied(a4Svg));
  denyOrHold(
    id: 'EQ-A4.mime_js_html_svg',
    matrix: 'EQ-A',
    lens: 'EQ1',
    payload: 'upload JS + HTML + SVG (image/svg+xml) no private bucket',
    hit: a4Any
        ? (a4Svg.ok && !isDenied(a4Svg)
            ? a4Svg
            : (a4Js.ok && !isDenied(a4Js) ? a4Js : a4Html))
        : a4Svg,
    bd: 'js=${a4Js.status} html=${a4Html.status} svg=${a4Svg.status}',
    expectedDeny: '415 InvalidMimeType nos três',
    classeNova: true,
    persistedOverride: a4Any,
    title: 'mime JS/HTML/SVG aceite',
  );

  // A5 signed URL buyer2 em disputa buyer1
  final a5Signed = await c.signObject(alienKey, jwt: c.buyer2Jwt);
  final a5Url = a5Signed ??
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$alienKey';
  final a5Ok = await proofOkRpc(a5Url, c.buyerId!, hp.oid);
  final a5Get = await c.storageGet(alienKey, jwt: c.buyerJwt);
  denyOrHold(
    id: 'EQ-A5.signed_url_buyer2',
    matrix: 'EQ-A',
    lens: 'EQ6',
    payload: 'RPC proof_ok URL signed B2 em disputa B1 + GET objecto B2 como B1',
    hit: a5Ok,
    bd: 'rpc=${a5Ok.body} getB2asB1=${a5Get.brief}',
    expectedDeny: 'rpc false + GET NoSuchKey/403',
    persistedOverride: rpcTrue(a5Ok) || (a5Get.ok && !isDenied(a5Get)),
    title: 'URL prova outro buyer',
    severity: 'P1',
  );

  // A6 MOVE dest prefixo alheio
  final a6Src = c.disputeObj(c.buyerId!, hp.oid, 'move-src.png');
  await c.storageUpload(objectName: a6Src, bytes: pngBytes, jwt: c.buyerJwt);
  final a6Dest = 'order_disputes/${c.buyer2Id}/$alienOid/moved.png';
  final a6 = await c.storageMove(
    sourceKey: a6Src,
    destKey: a6Dest,
    jwt: c.buyerJwt,
  );
  final a6Get = await c.storageGet(a6Dest, jwt: c.buyerJwt);
  final a6Loot = a6.ok && !isDenied(a6) && a6Get.ok && !isDenied(a6Get);
  denyOrHold(
    id: 'EQ-A6.storage_move_alien_prefix',
    matrix: 'EQ-A',
    lens: 'EQ1',
    payload: 'POST /object/move source=próprio dest=order_disputes/{B2}/…',
    hit: a6,
    bd: 'move=${a6.brief} get=${a6Get.brief} loot=$a6Loot',
    expectedDeny: '403 RLS move/dest',
    classeNova: true,
    persistedOverride: a6Loot,
    title: 'storage MOVE para prefixo alheio',
    severity: 'P1',
  );

  // A6b COPY dest prefixo alheio (classe_nova vs MOVE)
  final a6bSrc = c.disputeObj(c.buyerId!, hp.oid, 'copy-src.png');
  await c.storageUpload(objectName: a6bSrc, bytes: pngBytes, jwt: c.buyerJwt);
  final a6bDest = 'order_disputes/${c.buyer2Id}/$alienOid/copied.png';
  final a6b = await c.storageCopy(
    sourceKey: a6bSrc,
    destKey: a6bDest,
    jwt: c.buyerJwt,
  );
  final a6bGet = await c.storageGet(a6bDest, jwt: c.buyerJwt);
  final a6bLoot = a6b.ok && !isDenied(a6b) && a6bGet.ok && !isDenied(a6bGet);
  denyOrHold(
    id: 'EQ-A6b.storage_copy_alien_prefix',
    matrix: 'EQ-A',
    lens: 'EQ1',
    payload: 'POST /object/copy source=próprio dest=order_disputes/{B2}/…',
    hit: a6b,
    bd: 'copy=${a6b.brief} get=${a6bGet.brief} loot=$a6bLoot',
    expectedDeny: '403 RLS copy/dest',
    classeNova: true,
    persistedOverride: a6bLoot,
    title: 'storage COPY para prefixo alheio',
    severity: 'P1',
  );

  // A7 GraphQL revoke collection
  final a7gql = await c.req(
    'POST',
    '/graphql/v1',
    jwt: c.buyerJwt,
    body: {
      'query':
          'query { batata_private_object_revokedCollection { edges { node { object_path } } } }',
    },
  );
  final gqlLeak = a7gql.ok &&
      !isDenied(a7gql) &&
      a7gql.body.contains('object_path') &&
      !a7gql.body.contains('errors');
  denyOrHold(
    id: 'EQ-A7.graphql_revoke_collection',
    matrix: 'EQ-A',
    lens: 'EQ2',
    payload: 'POST /graphql/v1 batata_private_object_revokedCollection',
    hit: a7gql,
    bd: 'gqlLeak=$gqlLeak body=${clip(a7gql.body, 160)}',
    expectedDeny: '401/403 / errors / collection ausente',
    classeNova: true,
    persistedOverride: gqlLeak,
    title: 'GraphQL lê revoke registry',
    severity: 'P1',
  );

  // A8 RPC revoke path ../ (objecto alheio intacto)
  final a8Trav =
      'order_disputes/${c.buyerId}/../${c.buyer2Id}/$alienOid/rteq-secret.png';
  final a8 = await c.revokePath(a8Trav, jwt: c.buyerJwt);
  final a8GetB2 = await c.storageGet(alienKey, jwt: c.buyer2Jwt);
  final a8RevReal = await c.rest(
    'GET',
    'batata_private_object_revoked?object_path=eq.$alienKey&select=object_path',
    service: true,
  );
  final a8Touched = a8GetB2.status == 404 || a8RevReal.list.isNotEmpty;
  denyOrHold(
    id: 'EQ-A8.revoke_rpc_dotdot_alien',
    matrix: 'EQ-A',
    lens: 'EQ2',
    payload: 'RPC revoke p_path=order_disputes/{B1}/../{B2}/… + oráculo GET B2',
    hit: a8,
    bd: 'rpc=${a8.body} getB2=${a8GetB2.status} registryReal n=${a8RevReal.list.length} touched=$a8Touched',
    expectedDeny: 'RPC false/42501 OU true só no path literal; objecto B2 intacto',
    classeNova: true,
    persistedOverride: a8Touched,
    title: 'revoke RPC traversal toca objecto alheio',
    severity: 'P1',
  );

  // ===========================================================================
  // EQ-C5 happy disputa (precisa did para B4/D3) + EQ-E1 segundo pago
  // ===========================================================================
  final d1Ins = await c.insertDispute(orderId: hp.oid, photos: [signedOrOwn]);
  var did = d1Ins.firstId;
  passHappy(
    id: 'EQ-C5.happy_dispute_png_signed',
    matrix: 'EQ-C',
    lens: 'EQ4',
    payload: 'POST order_disputes proof signed própria em concluido (4242)',
    hit: d1Ins,
    bd: 'id=$did photos=${clip(d1Ins.map?['proof_photos'], 120)} pi=${hp.pi}',
    ok: d1Ins.status == 201 && did != null,
    title: 'disputa+prova signed 201 (order 1)',
  );

  // ===========================================================================
  // EQ-B Revoke / proof_ok (≥5)
  // ===========================================================================

  // B1 DELETE + revoke + proof_ok false + JWT INSERT/SELECT 403 (residual 1)
  final b1Path = c.disputeObj(c.buyerId!, hp.oid, 'revoke.png');
  await c.storageUpload(objectName: b1Path, bytes: pngBytes, jwt: c.buyerJwt);
  final b1Signed = await c.signObject(b1Path, jwt: c.buyerJwt);
  final b1Del = await c.storageDelete(b1Path, jwt: c.buyerJwt);
  final b1AuthAfter = await c.storageGet(b1Path, jwt: c.buyerJwt);
  final b1Rev = await c.revokePath(b1Path, jwt: c.buyerJwt);
  final b1Canon =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$b1Path';
  final b1OkAfter = await proofOkRpc(b1Canon, c.buyerId!, hp.oid);
  final b1AuthGone = isDenied(b1AuthAfter) || b1AuthAfter.status == 404;
  final b1ProofStillTrue = rpcTrue(b1OkAfter);

  final b1AlienPath =
      'order_disputes/${c.buyer2Id}/${hp.oid}/hostile-revoke.png';
  final b1Ins = await c.revokedInsert(b1AlienPath, jwt: c.buyerJwt);
  final b1Sel = await c.revokedSelect(jwt: c.buyerJwt);
  final b1Wrote = b1Ins.ok && !isDenied(b1Ins) && !emptyOk(b1Ins);
  final b1Leak = b1Sel.ok &&
      !isDenied(b1Sel) &&
      b1Sel.list.isNotEmpty &&
      b1Sel.list.any((e) =>
          e is Map && '${e['object_path']}'.contains('${c.buyer2Id}'));
  final b1Closed =
      b1AuthGone && !b1ProofStillTrue && !b1Wrote && !b1Leak;
  denyOrHold(
    id: 'EQ-B1.delete_revoke_jwt_403',
    matrix: 'EQ-B',
    lens: 'EQ2',
    payload:
        'DELETE+revoke+proof_ok + JWT INSERT/SELECT batata_private_object_revoked',
    hit: b1ProofStillTrue
        ? b1OkAfter
        : (b1Wrote || b1Leak ? b1Ins : b1OkAfter),
    bd: 'del=${b1Del.status} auth=${b1AuthAfter.status} rev=${b1Rev.body} proof_ok=${b1OkAfter.body} ins=${b1Ins.status} sel=${b1Sel.status} wrote=$b1Wrote leak=$b1Leak',
    expectedDeny: 'auth 404; proof_ok false; INSERT/SELECT 401/403',
    residual: b1Closed,
    classeNova: false,
    persistedOverride: !b1Closed,
    title: 'revoke sticky + JWT GRANT 403',
    severity: b1Wrote || b1Leak ? 'P1' : 'P2',
  );

  // B2 signed GET pós-DELETE (não residual — DQ P2)
  HttpHit b2cdn = HttpHit(0, 'no_sign', null);
  if (b1Signed != null) {
    b2cdn = await c.storageGetSigned(b1Signed);
  }
  final cdn200 = b2cdn.ok &&
      !isDenied(b2cdn) &&
      (b2cdn.body.contains('PNG') ||
          b2cdn.status == 200 && !b2cdn.body.toLowerCase().contains('nosuchkey'));
  denyOrHold(
    id: 'EQ-B2.signed_get_after_delete',
    matrix: 'EQ-B',
    lens: 'EQ2',
    payload: 'GET da signed URL após DELETE+revoke (auth já 404)',
    hit: b2cdn,
    bd: 'auth=${b1AuthAfter.status} signed=${b2cdn.status} bytes=${b2cdn.body.length} cdn200=$cdn200',
    expectedDeny: '404/400 NoSuchKey após DELETE',
    classeNova: true,
    persistedOverride: cdn200,
    title: 'signed GET 200 pós-DELETE',
    severity: 'P2',
  );

  // B3 re-upload mesmo path → proof_ok ainda false
  final b3Path = c.disputeObj(c.buyerId!, hp.oid, 'reup.png');
  await c.storageUpload(objectName: b3Path, bytes: pngBytes, jwt: c.buyerJwt);
  await c.storageDelete(b3Path, jwt: c.buyerJwt);
  await c.revokePath(b3Path, jwt: c.buyerJwt);
  final b3Re = await c.storageUpload(
    objectName: b3Path,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final b3Canon =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$b3Path';
  final b3Ok = await proofOkRpc(b3Canon, c.buyerId!, hp.oid);
  denyOrHold(
    id: 'EQ-B3.reupload_same_path_proof_ok',
    matrix: 'EQ-B',
    lens: 'EQ3',
    payload: 'DELETE+revoke → POST mesmo path → proof_ok canónico',
    hit: b3Ok,
    bd: 're=${b3Re.status} proof_ok=${b3Ok.body}',
    expectedDeny: 'proof_ok false (registry sticky)',
    classeNova: true,
    persistedOverride: rpcTrue(b3Ok),
    title: 're-upload apaga revoke no proof_ok',
    severity: 'P2',
  );

  // B4 proof URL forjada / query token trick
  final b4Ok = await proofOkRpc(a5Url, c.buyerId!, hp.oid);
  HttpHit b4Patch = HttpHit(0, 'no_did', null);
  bool b4Kept = false;
  if (did != null) {
    b4Patch = await c.patchDispute(did, {
      'proof_photos': [a5Url],
    });
    b4Kept =
        '${(await c.disputeRow(did))?['proof_photos']}'.contains('$alienOid');
  }
  denyOrHold(
    id: 'EQ-B4.forged_alien_proof_url',
    matrix: 'EQ-B',
    lens: 'EQ3',
    payload: 'proof_ok + persist URL signed B2 na disputa B1',
    hit: b4Ok,
    bd: 'rpc=${b4Ok.body} persist=${b4Patch.brief} kept=$b4Kept',
    expectedDeny: 'proof_ok false; persist 400/200[]',
    classeNova: true,
    persistedOverride: rpcTrue(b4Ok) || b4Kept,
    title: 'prova path alheio forjada',
    severity: 'P1',
  );

  // B4b query token trick (classe_nova): suffix hostil DEPOIS de ?token=
  final tokenTrick = '$signedOrOwn?token=deadbeef&x=../${c.buyer2Id}/$alienOid/x.png';
  final b4bOk = await proofOkRpc(tokenTrick, c.buyerId!, hp.oid);
  // true no próprio signed (query cortada) = defesa. HOLD só se true E persist alien.
  HttpHit b4bPatch = HttpHit(0, 'no_did', null);
  bool b4bKept = false;
  if (did != null) {
    b4bPatch = await c.patchDispute(did, {
      'proof_photos': [tokenTrick],
    });
    b4bKept =
        '${(await c.disputeRow(did))?['proof_photos']}'.contains('$alienOid');
  }
  denyOrHold(
    id: 'EQ-B4b.query_token_trick',
    matrix: 'EQ-B',
    lens: 'EQ3',
    payload: 'proof_ok URL própria + ?token= + path B2 (sem loot se query cortada)',
    hit: b4bOk,
    bd: 'rpc=${b4bOk.body} persist=${b4bPatch.brief} keptAlien=$b4bKept',
    expectedDeny: 'proof_ok no máximo sobre URL própria; persist sem path B2',
    classeNova: true,
    persistedOverride: b4bKept,
    title: 'query token trick persiste path alheio',
    severity: 'P1',
  );

  // B5 revoke mid-disputa + reply UI deny
  final b5pay = await mustPay('EQ4', qty: 1);
  if (!await c.toEnviado(b5pay.oid)) throw StateError('env b5');
  if (!await c.toConcluido(b5pay.oid)) throw StateError('conc b5');
  final b5Path = c.disputeObj(c.buyerId!, b5pay.oid, 'mid.png');
  await c.storageUpload(objectName: b5Path, bytes: pngBytes, jwt: c.buyerJwt);
  final b5Signed = await c.signObject(b5Path, jwt: c.buyerJwt);
  final b5Url = b5Signed ??
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$b5Path';
  final b5Ins = await c.insertDispute(orderId: b5pay.oid, photos: [b5Url]);
  final b5did = b5Ins.firstId;
  await c.storageDelete(b5Path, jwt: c.buyerJwt);
  final b5Rev = await c.revokePath(b5Path, jwt: c.buyerJwt);
  final b5Canon =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$b5Path';
  final b5Ok = await proofOkRpc(b5Canon, c.buyerId!, b5pay.oid);
  HttpHit b5Reply = HttpHit(0, 'no_did', null);
  bool b5ReplyKept = false;
  if (b5did != null) {
    b5Reply = await c.insertReply(
      disputeId: b5did,
      photos: [b5Canon],
      message: 'RTEQ B5 reply com URL revogada',
    );
    b5ReplyKept = b5Reply.status == 201 &&
        '${b5Reply.map?['proof_photos'] ?? ''}'.contains('mid.png');
  }
  denyOrHold(
    id: 'EQ-B5.revoke_mid_dispute_reply',
    matrix: 'EQ-B',
    lens: 'EQ3',
    payload: 'disputa 201 → DELETE+revoke → proof_ok + POST reply com URL morta',
    hit: b5Ok,
    bd: 'ins=${b5Ins.status} did=$b5did rev=${b5Rev.body} proof_ok=${b5Ok.body} reply=${b5Reply.status} replyKept=$b5ReplyKept',
    expectedDeny: 'proof_ok false; reply 400/denied',
    classeNova: true,
    persistedOverride: rpcTrue(b5Ok) || b5ReplyKept,
    title: 'reply aceita URL revogada a meio da disputa',
    severity: 'P2',
  );

  // ===========================================================================
  // EQ-C Disputa FSM (≥5)
  // ===========================================================================

  // C1 disputa order alheia
  final c1 = await c.insertDispute(
    orderId: hp.oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  denyOrHold(
    id: 'EQ-C1.dispute_order_alheia',
    matrix: 'EQ-C',
    lens: 'EQ6',
    payload: 'B2 POST order_disputes na order paga de B1',
    hit: c1,
    bd: 'oid=${hp.oid} id=${c1.firstId}',
    expectedDeny: '403 RLS / buyer_id mismatch',
    title: 'disputa order alheia',
    severity: 'P1',
  );

  // C2a janela `pago` (classe_nova — não enviado/concluido)
  final pagoOnly = await mustPay('EQ4', qty: 1);
  final c2a = await c.insertDispute(orderId: pagoOnly.oid);
  denyOrHold(
    id: 'EQ-C2a.window_pago',
    matrix: 'EQ-C',
    lens: 'EQ4',
    payload: 'POST disputa em status=pago (ainda não enviado)',
    hit: c2a,
    bd: 'status=${(await c.orderRow(pagoOnly.oid))?['status']} id=${c2a.firstId}',
    expectedDeny: '403 só concluido/entregue',
    classeNova: true,
    title: 'disputa na janela pago',
  );

  // C2b janela enviado (residual anti-atrofia 1)
  if (!await c.toEnviado(pagoOnly.oid)) throw StateError('env pagoOnly');
  final c2b = await c.insertDispute(orderId: pagoOnly.oid);
  denyOrHold(
    id: 'EQ-C2b.window_enviado',
    matrix: 'EQ-C',
    lens: 'EQ4',
    payload: 'POST disputa em status=enviado (ainda não concluido)',
    hit: c2b,
    bd: 'status=${(await c.orderRow(pagoOnly.oid))?['status']} id=${c2b.firstId}',
    expectedDeny: '403 só concluido/entregue',
    residual: true,
    title: 'disputa na janela enviado',
  );

  // C2c pós-release
  final win = await mustPay('EQ4', qty: 1);
  if (!await c.toEnviado(win.oid)) throw StateError('env win');
  if (!await c.toConcluido(win.oid)) throw StateError('conc win');
  await c.patchOrder(win.oid, {
    'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String(),
  }, service: true);
  final c2c = await c.insertDispute(orderId: win.oid);
  denyOrHold(
    id: 'EQ-C2c.window_after_release',
    matrix: 'EQ-C',
    lens: 'EQ4',
    payload: 'POST disputa após wallet_release_processed_at',
    hit: c2c,
    bd: 'oid=${win.oid} id=${c2c.firstId}',
    expectedDeny: '403 residual janela clássica',
    title: 'disputa fora de janela pós-release',
  );

  // C3 disputa∥refund
  final race = await mustPay('EQ7', qty: 1);
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
  final mintC3 = q1 > q0 && dRace.status == 201 && rfRace.ok && !isDenied(rfRace);
  c.note('C3.race', 'disputa∥refund', {
    'd': dRace.brief,
    'rf': rfRace.brief,
    'qty': '$q0→$q1',
    'status': raceRow?['status'],
    'refund_id': raceRow?['stripe_refund_id'],
    'Δb': (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0),
    'Δs': (w1['seller'] ?? 0) - (w0['seller'] ?? 0),
  }, lens: 'EQ7');
  denyOrHold(
    id: 'EQ-C3.dispute_refund_race',
    matrix: 'EQ-C',
    lens: 'EQ7',
    payload: 'Future.wait POST disputa ∥ Edge refund-order',
    hit: bothWon ? rfRace : (dRace.status == 201 ? dRace : rfRace),
    bd: 'd=${dRace.status} rf=${rfRace.status} qty $q0→$q1 bothWon=$bothWon mint=$mintC3 st=${raceRow?['status']}',
    expectedDeny:
        'XOR: disputa 201 e refund 403, ou refund 200 e disputa 403; stock +1 no máximo uma vez',
    persistedOverride: bothWon,
    title: 'race disputa∥refund cria dinheiro+stock',
    severity: 'P0',
  );

  // C4 disputa∥release (clawback / 1 efeito)
  final relPay = await mustPay('EQ7', qty: 1);
  await c.plantConcluidoMao(relPay.oid);
  final qRel0 = numOf((await c.productRow(relPay.pid))?['quantity'])?.round() ?? -1;
  final wRel0 = await c.wallets();
  final relRaced = await parallel([
    c.tryRelease(relPay.oid, jwt: c.buyerJwt),
    c.insertDispute(orderId: relPay.oid, photos: [signedOrOwn]),
  ]);
  final relHit = relRaced[0];
  final dispRel = relRaced[1];
  final qRel1 = numOf((await c.productRow(relPay.pid))?['quantity'])?.round() ?? -1;
  final wRel1 = await c.wallets();
  final dWalletRel = (wRel1['seller'] ?? 0) - (wRel0['seller'] ?? 0);
  final released = c.releasedTrue(relHit);
  final dispOpen = dispRel.status == 201;
  final twoEffects = released && dWalletRel > 0 && dispOpen;
  final mintC4 = qRel1 > qRel0;
  c.note('C4.race', 'disputa∥release', {
    'rel': relHit.brief,
    'd': dispRel.brief,
    'qty': '$qRel0→$qRel1',
    'Δs': dWalletRel,
    'released': released,
    'dispOpen': dispOpen,
  }, lens: 'EQ7');
  denyOrHold(
    id: 'EQ-C4.dispute_release_race',
    matrix: 'EQ-C',
    lens: 'EQ7',
    payload: 'Future.wait RPC release ∥ POST disputa (plant concluido+mão)',
    hit: twoEffects ? relHit : (dispOpen ? dispRel : relHit),
    bd: 'rel=${relHit.body} d=${dispRel.status} Δs=$dWalletRel qty $qRel0→$qRel1 two=$twoEffects mint=$mintC4',
    expectedDeny: '1 efeito líquido (crédito XOR disputa); stock Δ=0 mint',
    classeNova: true,
    persistedOverride: twoEffects,
    title: 'race disputa∥release credita E abre disputa',
    severity: 'P1',
  );

  // ===========================================================================
  // EQ-D Portes / label (≥4)
  // ===========================================================================

  // D1 PATCH portes após cs_ open
  final d1sku = await c.createProduct(title: '$prefix-d1', qty: 2);
  String? d1oid;
  if (d1sku != null) {
    d1oid = await c.insertOrder(
      productId: d1sku,
      jwt: c.buyerJwt,
      shipping: 'entrega em mão',
    );
  }
  HttpHit d1cs = HttpHit(0, 'no_order', null);
  HttpHit d1patch = HttpHit(0, 'no_order', null);
  Map<String, dynamic>? d1before;
  Map<String, dynamic>? d1after;
  if (d1oid != null) {
    d1cs = await c.checkout(
      orderId: d1oid,
      productId: d1sku,
      amount: 1,
      shipping: 'mao',
    );
    d1before = await c.orderRow(d1oid);
    d1patch = await c.patchOrder(d1oid, {'shipping_method': 'ctt'});
    d1after = await c.orderRow(d1oid);
  }
  final d1Changed = d1after != null &&
      '${d1after['shipping_method']}' != '${d1before?['shipping_method']}' &&
      '${d1after['shipping_method']}'.toLowerCase().contains('ctt');
  denyOrHold(
    id: 'EQ-D1.patch_ship_after_cs',
    matrix: 'EQ-D',
    lens: 'EQ5',
    payload: 'PATCH shipping=ctt após Session cs_ open',
    hit: d1patch,
    bd: 'cs=${d1cs.status} sid=${d1cs.sessionId} ${d1before?['shipping_method']}→${d1after?['shipping_method']} changed=$d1Changed',
    expectedDeny: 'selo mão intacto; 200[] / 42501',
    persistedOverride: d1Changed,
    title: 'selo portes após cs_ open',
    severity: 'P1',
  );

  // D2 PATCH portes após pago
  final d2pay = await mustPay('EQ5', qty: 1);
  final d2b = await c.orderRow(d2pay.oid);
  final d2p = await c.patchOrder(d2pay.oid, {'shipping_method': 'ctt'});
  final d2a = await c.orderRow(d2pay.oid);
  final d2Changed = '${d2a?['shipping_method']}' != '${d2b?['shipping_method']}' &&
      '${d2a?['shipping_method']}'.toLowerCase().contains('ctt');
  denyOrHold(
    id: 'EQ-D2.patch_ship_after_pago',
    matrix: 'EQ-D',
    lens: 'EQ5',
    payload: 'PATCH shipping=ctt após pago Stripe TEST',
    hit: d2p,
    bd: 'paid ${d2b?['shipping_method']}→${d2a?['shipping_method']} changed=$d2Changed paid=${d2a?['amount_paid_cents']}',
    expectedDeny: 'selo mão intacto',
    persistedOverride: d2Changed,
    title: 'selo portes após pago',
    severity: 'P1',
  );

  // D3 label traversal / oid forjado / %252f
  final fakeOid = '11111111-1111-1111-1111-111111111111';
  final travLabel =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/${c.buyerId}/../$fakeOid/ok.png';
  HttpHit d3lab = HttpHit(0, 'no_did', null);
  Map<String, dynamic>? d3labRow;
  if (did != null) {
    d3lab = await c.patchDispute(did, {'return_label_url': travLabel});
    d3labRow = await c.disputeRow(did);
  }
  final d3labKept = '${d3labRow?['return_label_url'] ?? ''}'.contains(fakeOid) ||
      '${d3labRow?['return_label_url'] ?? ''}'.contains('../');
  denyOrHold(
    id: 'EQ-D3.label_traversal_forge_oid',
    matrix: 'EQ-D',
    lens: 'EQ5',
    payload: 'PATCH return_label_url …/{B1}/../{fakeOid}/ok.png',
    hit: d3lab,
    bd: 'stored=${clip(d3labRow?['return_label_url'], 160)} kept=$d3labKept',
    expectedDeny: '400 label_url_denied / 200[]',
    classeNova: true,
    persistedOverride: d3lab.ok && d3labKept,
    title: 'label traversal + order_id forjado',
    severity: 'P1',
  );

  // D3b %252f residual anti-atrofia
  if (did != null) {
    final ctrl252f =
        '${signedOrOwn}%252forder_disputes/${c.buyer2Id}/$alienOid/rteq-secret.png';
    final ctrlHit =
        await c.patchDispute(did, {'return_label_url': ctrl252f});
    final stored = await c.disputeRow(did);
    final persisted252f =
        ctrlHit.ok && '${stored?['return_label_url'] ?? ''}'.contains('%252f');
    denyOrHold(
      id: 'EQ-D3b.label_252f',
      matrix: 'EQ-D',
      lens: 'EQ5',
      payload: 'PATCH label %252f + path B2 (anti-atrofia)',
      hit: ctrlHit,
      bd: 'stored=${clip(stored?['return_label_url'], 140)} persisted=$persisted252f',
      expectedDeny: '400 order_dispute_label_url_denied',
      residual: true,
      persistedOverride: persisted252f,
      title: 'label %252f residual',
    );

    final slashHit = await c.patchDispute(
        did, {'return_label_url': '$signedOrOwn//extra.png'});
    final slashStored = await c.disputeRow(did);
    final slashKept =
        '${slashStored?['return_label_url'] ?? ''}'.contains('//extra');
    denyOrHold(
      id: 'EQ-D3c.slashslash_after_host',
      matrix: 'EQ-D',
      lens: 'EQ5',
      payload: 'PATCH label signed + //extra.png após ficheiro',
      hit: slashHit,
      bd: 'stored=${clip(slashStored?['return_label_url'], 100)} kept=$slashKept',
      expectedDeny: '400 // após host',
      residual: true,
      persistedOverride: slashKept,
      title: '// após host residual',
    );
  }

  // D4 seller2 lê label/disputa buyer1
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
  final d4RowS2 = await c.rest(
    'GET',
    'order_disputes?id=eq.${did ?? '00000000-0000-0000-0000-000000000001'}&select=id,return_label_url,proof_photos,buyer_id,order_id',
    jwt: c.seller2Jwt,
  );
  final d4GetObj = await c.storageGet(labelPath, jwt: c.seller2Jwt);
  final d4List = await c.storageList(
    prefix: 'order_disputes/${c.buyerId}/',
    jwt: c.seller2Jwt,
  );
  final d4LeakRow = d4RowS2.ok &&
      !isDenied(d4RowS2) &&
      !emptyOk(d4RowS2) &&
      (d4RowS2.map?['return_label_url'] != null || d4RowS2.list.isNotEmpty);
  final d4LootObj = d4GetObj.ok && !isDenied(d4GetObj);
  final d4ListLeak = d4List.ok && !isDenied(d4List) && d4List.list.isNotEmpty;
  denyOrHold(
    id: 'EQ-D4.seller2_reads_label_buyer1',
    matrix: 'EQ-D',
    lens: 'EQ6',
    payload: 'S2 GET order_disputes id B1 + GET/LIST storage label B1',
    hit: d4LeakRow ? d4RowS2 : (d4LootObj ? d4GetObj : d4List),
    bd: 'rowS2=${d4RowS2.status} n=${d4RowS2.list.length} getObj=${d4GetObj.status} list=${d4List.status} leakRow=$d4LeakRow lootObj=$d4LootObj listLeak=$d4ListLeak',
    expectedDeny: '403/[] RLS; storage NoSuchKey',
    classeNova: true,
    persistedOverride: d4LeakRow || d4LootObj || d4ListLeak,
    title: 'seller2 lê label/prova de buyer1',
    severity: 'P1',
  );

  // ===========================================================================
  // EQ-E Caixa / regressão (≥2)
  // ===========================================================================

  // E1 2.º pago 4242 + disputa feliz
  final e1 = await mustPay('EQ8', qty: 1);
  if (!await c.toEnviado(e1.oid)) throw StateError('env e1');
  if (!await c.toConcluido(e1.oid)) throw StateError('conc e1');
  final e1Path = c.disputeObj(c.buyerId!, e1.oid, 'e1.png');
  await c.storageUpload(objectName: e1Path, bytes: pngBytes, jwt: c.buyerJwt);
  final e1Signed = await c.signObject(e1Path, jwt: c.buyerJwt);
  final e1Url = e1Signed ??
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$e1Path';
  final e1Ins = await c.insertDispute(orderId: e1.oid, photos: [e1Url]);
  passHappy(
    id: 'EQ-E1.second_paid_happy_dispute',
    matrix: 'EQ-E',
    lens: 'EQ8',
    payload: '2.º setup_paid_order 4242 + POST disputa PNG signed',
    hit: e1Ins,
    bd: 'oid=${e1.oid} pi=${e1.pi} did=${e1Ins.firstId} paid=${(await c.orderRow(e1.oid))?['amount_paid_cents']}',
    ok: e1Ins.status == 201 && e1Ins.firstId != null,
    title: '2.º pago + disputa feliz 201',
  );

  // E2 stock Δ nas races C3/C4 = 0 mint
  final e2Mint = mintC3 || mintC4;
  denyOrHold(
    id: 'EQ-E2.stock_delta_races_no_mint',
    matrix: 'EQ-E',
    lens: 'EQ8',
    payload: 'oráculo qty C3 disputa∥refund + C4 disputa∥release',
    hit: e2Mint ? rfRace : dRace,
    bd: 'C3 qty $q0→$q1 mintC3=$mintC3 C4 qty $qRel0→$qRel1 mintC4=$mintC4',
    expectedDeny: 'Δ stock nas races = 0 mint (sem 2.ª unidade inventada)',
    classeNova: true,
    persistedOverride: e2Mint,
    title: 'races mintam stock',
    severity: 'P0',
  );

  await c.dumpAll('pass1.json');
  stdout.writeln(
      'DONE probes=${c.probes.length} findings=${c.findings.length} lenses=${c.lensesHit.toList()..sort()}');
}
