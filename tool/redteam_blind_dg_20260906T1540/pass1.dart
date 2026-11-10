/// RED TEAM CEGO DG — pass 1. Staging only. Não corrige.
/// Matriz A/B/C ≥12 · lentes DG1–DG7 · pós-CVDA: // só após host.
import 'dart:convert';
import '_rtdg.dart';

const pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

bool has54000(Object? v) => '$v'.contains('54000');

bool isDenied(HttpHit h) {
  final raw = h.body.toLowerCase();
  return h.status == 400 ||
      h.status == 403 ||
      h.status == 409 ||
      h.status == 415 ||
      raw.contains('denied') ||
      raw.contains('23514') ||
      raw.contains('forbidden') ||
      raw.contains('already_exists') ||
      raw.contains('sem permissão') ||
      raw.contains('sem permiss');
}

void main() async {
  final c = Rtci.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  c.well('DG-A');
  c.well('DG-B');
  c.well('DG-C');

  Future<({String oid, String pid, String? pi})> mustPay(String lens,
      {int qty = 1}) async {
    final paid = await c.payToPago(lens: lens, initialQty: qty);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  void denyOrHold({
    required String id,
    required String matrix,
    required String lens,
    required String payload,
    required HttpHit hit,
    String? bd,
    required String expectedDeny,
    bool residual = false,
    bool controlNoCount = false,
    String severity = 'P2',
    String? title,
  }) {
    final persisted = hit.ok && !isDenied(hit);
    if (residual) {
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: hit.brief,
        bd: bd,
        result: persisted ? 'RESIDUAL' : 'FAIL',
      );
      return;
    }
    if (controlNoCount) {
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: hit.brief,
        bd: bd,
        result: persisted ? 'HOLD' : 'FAIL',
      );
      if (persisted) {
        c.note(id, 'controlo exacto DA — NÃO CONTAR', hit, lens: lens);
      } else {
        c.block(id, lens, title ?? id, hit);
      }
      return;
    }
    if (has54000(hit) && matrix == 'DG-A') {
      c.hold(
        id: id,
        lens: lens,
        severity: 'P2',
        title: title ?? 'URL limpa rebentou 54000',
        actor: 'buyer JWT / service RPC',
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
      );
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
  }) {
    if (has54000(hit) || !ok) {
      c.hold(
        id: id,
        lens: lens,
        severity: severity,
        title: title ?? 'Happy path partido',
        actor: 'buyer JWT',
        pre: payload,
        repro: id,
        expected: '200/201 sem 54000',
        obtained: hit.brief,
      );
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: hit.brief,
        bd: bd,
        result: 'HOLD',
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
      );
    }
  }

  Future<HttpHit> canonRpc(String url) {
    return c.rpc(
      'batata_storage_url_path_canonical',
      {'p_url': url},
      service: true,
    );
  }

  Future<HttpHit> proofOkRpc(String url, String buyer, String oid) {
    return c.rpc(
      'batata_dispute_proof_url_ok',
      {'p_url': url, 'p_buyer': buyer, 'p_oid': oid},
      service: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Fixture HP: Stripe TEST → enviado → concluido + PNG assinado próprio
  // ---------------------------------------------------------------------------
  final hp = await mustPay('DG3', qty: 1);
  if (!await c.toEnviado(hp.oid)) throw StateError('enviado hp');
  if (!await c.toConcluido(hp.oid)) throw StateError('concluido hp');
  final minePath = c.disputeObj(c.buyerId!, hp.oid, 'ok.png');
  final up = await c.storageUpload(
    objectName: minePath,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final signed = await c.signObject(minePath, jwt: c.buyerJwt);
  c.note('DG1.upload', 'PNG próprio assinado', {
    'up': up.brief,
    'signed': signed,
    'path': minePath,
  }, lens: 'DG1');

  final alienKey =
      'order_disputes/${c.buyer2Id}/00000000-0000-0000-0000-00000000dg02/rtdg-secret.png';
  final alienUp = await c.storageUpload(
    objectName: alienKey,
    bytes: pngBytes,
    jwt: c.buyer2Jwt,
  );
  c.note('DG4.alien', 'objecto B2', alienUp.brief, lens: 'DG4');

  String ownSign(String file) =>
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/${c.buyerId}/${hp.oid}/$file';

  String ownAuth(String file) =>
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/authenticated/fleaber_private/'
      'order_disputes/${c.buyerId}/${hp.oid}/$file';

  // ---------------------------------------------------------------------------
  // DG-A Canonical / happy (≥3) — obrigatório feliz
  // ---------------------------------------------------------------------------
  final canonSimple = await canonRpc('https://example.com/a');
  c.note('A1.canon_simple', 'RPC https://example.com/a', canonSimple.brief,
      lens: 'DG1');
  passHappy(
    id: 'DG-A1.canon_simple',
    matrix: 'DG-A',
    lens: 'DG2',
    payload: 'RPC batata_storage_url_path_canonical https://example.com/a',
    hit: canonSimple,
    bd: has54000(canonSimple) ? '54000' : '${canonSimple.body}',
    ok: canonSimple.ok && !has54000(canonSimple),
    title: 'RPC URL limpa sem 54000',
  );

  final signedOrOwn = signed ?? ownSign('ok.png');
  final canonSigned = await canonRpc(signedOrOwn);
  c.note('A1.canon_signed', 'RPC signed PNG próprio', canonSigned.brief,
      lens: 'DG1');
  passHappy(
    id: 'DG-A1.canon_signed',
    matrix: 'DG-A',
    lens: 'DG2',
    payload: 'RPC canonical signed PNG próprio (https path normal)',
    hit: canonSigned,
    bd: has54000(canonSigned) ? '54000' : clip(canonSigned.body, 180),
    ok: canonSigned.ok && !has54000(canonSigned),
    title: 'RPC signed URL limpa sem 54000',
  );

  final proofClean = await proofOkRpc(signedOrOwn, c.buyerId!, hp.oid);
  c.note('A1.proof_ok_clean', 'RPC batata_dispute_proof_url_ok signed próprio', {
    'hit': proofClean.brief,
    'body': proofClean.body,
  }, lens: 'DG1');
  final proofCleanTrue = proofClean.ok &&
      (proofClean.body == 'true' || proofClean.json == true);
  passHappy(
    id: 'DG-A1.proof_ok_clean',
    matrix: 'DG-A',
    lens: 'DG1',
    payload: 'RPC batata_dispute_proof_url_ok URL signed própria',
    hit: proofClean,
    bd: 'ok=${proofClean.body}',
    ok: proofCleanTrue && !has54000(proofClean),
    title: 'Helper aceita URL signed própria (// do scheme ignorado)',
  );

  final insPhoto = await c.insertDispute(
    orderId: hp.oid,
    photos: [signedOrOwn],
  );
  c.note('A2.insert_photo', 'INSERT disputa proof signed própria', {
    'hit': insPhoto.brief,
    'photos': insPhoto.map?['proof_photos'],
    'status': insPhoto.map?['status'],
  }, lens: 'DG3');
  var did = insPhoto.firstId;
  final photoOk = insPhoto.status == 201 &&
      did != null &&
      !has54000(insPhoto) &&
      jsonEncode(insPhoto.map?['proof_photos'] ?? []).contains(hp.oid);
  passHappy(
    id: 'DG-A2.open_with_canonical_proof',
    matrix: 'DG-A',
    lens: 'DG3',
    payload: 'POST order_disputes proof_photos=[signed PNG próprio] → 201',
    hit: insPhoto,
    bd: 'did=$did status=${insPhoto.map?['status']} photos=${clip(insPhoto.map?['proof_photos'], 160)}',
    ok: photoOk,
    title: 'Abrir disputa + prova signed própria 201',
  );

  if (did == null) {
    final empty = await c.insertDispute(orderId: hp.oid);
    did = empty.firstId;
    c.note('A2.fallback_empty', 'INSERT vazio após falha com foto', empty.brief,
        lens: 'DG3');
  }
  if (did == null) {
    c.skip('DG-A', 'DG3', 'sem disputa — abort A/B/C', insPhoto);
    await c.dumpAll('pass1.json');
    return;
  }

  final labelClean = await c.patchDispute(did, {
    'return_label_url': signedOrOwn,
  }, jwt: c.buyerJwt);
  c.note('A3.label_clean', 'PATCH return_label_url signed própria',
      labelClean.brief,
      lens: 'DG1');
  passHappy(
    id: 'DG-A3.label_canonical',
    matrix: 'DG-A',
    lens: 'DG1',
    payload: 'PATCH return_label_url=signed PNG próprio https → 200',
    hit: labelClean,
    bd: 'url=${clip(labelClean.map?['return_label_url'], 160)}',
    ok: labelClean.ok &&
        !has54000(labelClean) &&
        (labelClean.map?['return_label_url']?.toString().isNotEmpty ?? false),
    title: 'Label URL signed própria 200',
  );

  // ---------------------------------------------------------------------------
  // DG-B Path hostil (≥5) — bypass NOVO, não exacto DA %252f%255c
  // ---------------------------------------------------------------------------
  Future<void> pathReply({
    required String id,
    required String payload,
    required String url,
    bool residual = false,
    bool controlNoCount = false,
    String severity = 'P2',
    String? title,
  }) async {
    final rpcHit = await proofOkRpc(url, c.buyerId!, hp.oid);
    final reply = await c.insertReply(
      disputeId: did!,
      photos: [url],
      message: 'RTDG $id',
    );
    final stored = jsonEncode(reply.map?['proof_photos'] ?? []);
    c.note(id, title ?? id, {
      'rpc_ok': rpcHit.brief,
      'hit': reply.brief,
      'photos': reply.map?['proof_photos'],
    }, lens: 'DG4');
    denyOrHold(
      id: id,
      matrix: 'DG-B',
      lens: 'DG4',
      payload: payload,
      hit: reply,
      bd: 'rpc=${rpcHit.body} photos=${clip(stored, 180)}',
      expectedDeny: '403/400 dispute_proof_url_denied',
      residual: residual,
      controlNoCount: controlNoCount,
      severity: severity,
      title: title,
    );
  }

  final prefixOwn = ownSign('ok.png');

  // B1 controlo exacto DA — ≤1, NÃO CONTAR se HOLD
  await pathReply(
    id: 'DG-B1.control_252f_255c',
    payload: r'controlo exacto DA %252f%255c + path B2',
    url: '$prefixOwn%252f%255c$alienKey',
    controlNoCount: true,
    title: r'controlo %252f%255c concat (não contar)',
  );

  // B2 NOVOS — unicode / backslash / // cru após host (não exacto DA)
  const u29f9 = '\u29F9'; // BIG REVERSE SOLIDUS
  const u2572 = '\u2572'; // BOX DRAWINGS LIGHT DIAGONAL UPPER LEFT TO LOWER RIGHT
  const u31d1 = '\u31D1'; // CJK STROKE SP
  await pathReply(
    id: 'DG-B2.unicode_big_revsolidus_29f9',
    payload: r'joiner U+29F9 BIG REVERSE SOLIDUS + path B2 (não DA)',
    url: '$prefixOwn$u29f9$alienKey',
    title: 'proof unicode slash U+29F9 (novo)',
  );
  await pathReply(
    id: 'DG-B2b.unicode_box_2572',
    payload: r'joiner U+2572 box-drawing other diagonal + path B2',
    url: '$prefixOwn$u2572$alienKey',
    title: 'proof unicode slash U+2572 (novo)',
  );
  await pathReply(
    id: 'DG-B2c.cjk_stroke_31d1',
    payload: r'joiner U+31D1 CJK STROKE SP + path B2',
    url: '$prefixOwn$u31d1$alienKey',
    title: 'proof unicode slash U+31D1 (novo)',
  );
  await pathReply(
    id: 'DG-B2d.raw_slashslash_after_file',
    payload: r'concat cru // após ficheiro próprio + extra.png (não %252f%255c)',
    url: '$prefixOwn//extra.png',
    title: r'proof // cru após host no path',
  );
  await pathReply(
    id: 'DG-B2e.object_sign_double_slash',
    payload: r'/object/sign//fleaber_private/ (// a meio do path após host)',
    url:
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign//fleaber_private/'
        'order_disputes/${c.buyerId}/${hp.oid}/ok.png',
    title: 'proof // no segmento sign (novo)',
  );
  await pathReply(
    id: 'DG-B2f.pct2f2f_after_file',
    payload: r'%2f%2f após ficheiro → canónico // (não %252f%255c)',
    url: '$prefixOwn%2f%2fextra.png',
    title: r'proof %2f%2f concat (novo)',
  );
  await pathReply(
    id: 'DG-B2g.single_252f_no_backslash',
    payload: r'%252f simples (um slash) + path B2 — não o par %252f%255c',
    url: '$prefixOwn%252f$alienKey',
    title: r'proof %252f simples concat (novo)',
  );

  // B3 .. / double-encode residual
  await pathReply(
    id: 'DG-B3.dotdot_slash',
    payload: r'%2e%2e%2f traversal (não %5c)',
    url: '$prefixOwn%2e%2e%2f$alienKey',
    title: r'proof ../ encoded → deny',
  );
  await pathReply(
    id: 'DG-B3b.residual_25252e',
    payload: r'residual CDCI %25252e%25252e%25252f (não contar)',
    url: '$prefixOwn%25252e%25252e%25252f$alienKey',
    residual: true,
    title: 'residual CDCI triple-dot (não contar)',
  );

  // B4 bucket public / prova B2 alheia
  final bucketPublic =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/fleaber_private/'
      'order_disputes/${c.buyerId}/${hp.oid}/ok.png';
  await pathReply(
    id: 'DG-B4.bucket_public',
    payload: '/object/public/fleaber_private/ + needle próprio',
    url: bucketPublic,
    title: 'bucket swap public → deny',
  );
  final signedAlien = await c.signObject(alienKey, jwt: c.buyer2Jwt);
  await pathReply(
    id: 'DG-B4b.proof_b2_on_a',
    payload: 'signed URL objecto B2 em disputa A',
    url: signedAlien ??
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$alienKey',
    title: 'prova B2 em disputa A → deny',
  );

  // B5 label evil / relativo / scheme-less + residual do fecho // após host
  Future<void> labelProbe({
    required String id,
    required String payload,
    required String url,
    bool residual = false,
    String severity = 'P2',
    String? title,
  }) async {
    final h = await c.patchDispute(did!, {'return_label_url': url},
        jwt: c.buyerJwt);
    final stored = '${h.map?['return_label_url'] ?? ''}';
    c.note(id, title ?? id, {
      'hit': h.brief,
      'stored': stored,
    }, lens: 'DG4');
    denyOrHold(
      id: id,
      matrix: 'DG-B',
      lens: 'DG4',
      payload: payload,
      hit: h,
      bd: 'stored=${clip(stored, 180)}',
      expectedDeny: '403/400 order_dispute_label_url_denied',
      residual: residual,
      severity: severity,
      title: title,
    );
  }

  await labelProbe(
    id: 'DG-B5.label_evil_host',
    payload: 'https://evil.example/…/order_disputes/{buyer}/{oid}/label.png',
    url:
        'https://evil.example/cdn/order_disputes/${c.buyerId}/${hp.oid}/label.png',
    title: 'label host evil + needle',
  );
  await labelProbe(
    id: 'DG-B5b.label_relative_needle',
    payload: 'relativo COM needle (sem https://)',
    url: '/storage/v1/object/sign/fleaber_private/$minePath',
    title: 'label relativo com needle',
  );
  await labelProbe(
    id: 'DG-B5c.label_schemeless_needle',
    payload: 'path scheme-less order_disputes/{b}/{oid}/ok.png',
    url: 'order_disputes/${c.buyerId}/${hp.oid}/ok.png',
    title: 'label scheme-less + needle',
  );
  await labelProbe(
    id: 'DG-B5d.label_host_suffix_evil',
    payload: 'host supabase.co.evil.com + needle próprio (novo vs DA)',
    url:
        'https://fxdknzrqjenzqcvnwqqq.supabase.co.evil.com/storage/v1/object/sign/fleaber_private/'
        'order_disputes/${c.buyerId}/${hp.oid}/ok.png',
    title: 'label host suffix .evil.com (novo)',
  );
  await labelProbe(
    id: 'DG-B5e.label_userinfo',
    payload: 'https://user@host/storage/… needle (novo)',
    url:
        'https://evil@fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
        'order_disputes/${c.buyerId}/${hp.oid}/ok.png',
    title: 'label userinfo @host (novo)',
  );
  await labelProbe(
    id: 'DG-B5f.label_single_252f_concat',
    payload: r'label %252f simples + path B2 (sem .., não %252f%255c)',
    url: '${ownAuth('ok.png')}%252f$alienKey',
    title: r'label concat %252f simples (novo)',
  );
  await labelProbe(
    id: 'DG-B5g.label_raw_slashslash',
    payload: r'label signed + //extra.png após host',
    url: '$prefixOwn//extra.png',
    title: r'label // cru após host',
  );
  await labelProbe(
    id: 'DG-B5h.label_javascript',
    payload: 'javascript:alert(1) com needle no comentário',
    url:
        'javascript:alert(1)//order_disputes/${c.buyerId}/${hp.oid}/x.png',
    title: 'label javascript: (novo)',
  );

  // ---------------------------------------------------------------------------
  // DG-C FSM / stock / refund (≥4)
  // ---------------------------------------------------------------------------
  final pedido = await c.patchOrder(
    hp.oid,
    {'status': 'pedido_devolucao'},
    jwt: c.buyerJwt,
  );
  var o = await c.orderRow(hp.oid);
  c.note('C2.pedido', 'buyer pedido_devolucao', {
    'hit': pedido.brief,
    'status': o?['status'],
  }, lens: 'DG5');
  passHappy(
    id: 'DG-C2.pedido_devolucao',
    matrix: 'DG-C',
    lens: 'DG5',
    payload: 'buyer PATCH status=pedido_devolucao',
    hit: pedido,
    bd: 'status=${o?['status']}',
    ok: o?['status']?.toString() == 'pedido_devolucao',
    title: 'FSM buyer pedido_devolucao',
  );

  final emDev = await c.patchOrder(
    hp.oid,
    {'status': 'em_devolucao'},
    jwt: c.buyerJwt,
  );
  o = await c.orderRow(hp.oid);
  final sellerReply = await c.insertReply(
    disputeId: did,
    jwt: c.sellerJwt,
    sender: c.sellerId,
    message: 'RTDG seller recebeu pedido de devolução.',
  );
  c.note('C2.steps', 'buyer em_devolucao + seller reply', {
    'em_dev': emDev.brief,
    'status': o?['status'],
    'seller_reply': sellerReply.brief,
  }, lens: 'DG5');
  passHappy(
    id: 'DG-C2b.buyer_seller_fsm',
    matrix: 'DG-C',
    lens: 'DG5',
    payload: 'buyer em_devolucao + seller reply disputa',
    hit: emDev,
    bd: 'status=${o?['status']} reply=${sellerReply.status}',
    ok: o?['status']?.toString() == 'em_devolucao' &&
        (sellerReply.ok || sellerReply.status == 201),
    title: 'FSM buyer+seller até em_devolucao',
  );

  final second = await c.insertDispute(orderId: hp.oid);
  c.note('C1.second', '2.ª disputa mesma order', second.brief, lens: 'DG5');
  denyOrHold(
    id: 'DG-C1.second_dispute',
    matrix: 'DG-C',
    lens: 'DG5',
    payload: '2.ª POST order_disputes mesma encomenda',
    hit: second,
    expectedDeny: '409 dispute_already_exists_for_order',
    title: '2.ª disputa recusada',
  );

  await c.patchOrder(hp.oid, {'status': 'devolucao_entregue'},
      jwt: c.sellerJwt);
  final qtyBefore = numOf((await c.productRow(hp.pid))?['quantity']) ?? 0;
  final wBefore = await c.wallets();
  final dev = await c.patchOrder(hp.oid, {'status': 'devolvida'},
      jwt: c.sellerJwt);
  o = await c.orderRow(hp.oid);
  final qtyMid = numOf((await c.productRow(hp.pid))?['quantity']) ?? 0;
  final rf = await c.refund(hp.oid);
  o = await c.orderRow(hp.oid);
  final qtyAfter = numOf((await c.productRow(hp.pid))?['quantity']) ?? 0;
  final wAfter = await c.wallets();
  final refunds = hp.pi == null ? null : await c.stripeRefunds(hp.pi!);
  var stripeN = 0;
  var stripeSum = 0;
  if (refunds?.json is Map) {
    final data = (refunds!.json as Map)['data'];
    if (data is List) {
      stripeN = data.length;
      for (final e in data) {
        if (e is Map) stripeSum += numOf(e['amount'])?.round() ?? 0;
      }
    }
  }
  final paidCents = numOf(o?['amount_paid_cents']) ?? 0;
  final dBuyer = (wAfter['buyer'] ?? 0) - (wBefore['buyer'] ?? 0);
  final dSeller = (wAfter['seller'] ?? 0) - (wBefore['seller'] ?? 0);
  final stockDelta = qtyAfter - qtyBefore;
  final stockOk = stockDelta <= 1 &&
      stockDelta >= 0 &&
      stripeN <= 1 &&
      (stripeSum <= paidCents || paidCents == 0);
  c.note('C3.stock_refund', 'stock restore no refund', {
    'dev': dev.brief,
    'refund': rf.brief,
    'status': o?['status'],
    'qty': '$qtyBefore→$qtyMid→$qtyAfter',
    'paid': paidCents,
    'stripe_n': stripeN,
    'stripe_sum': stripeSum,
    'dBuyer': dBuyer,
    'dSeller': dSeller,
  }, lens: 'DG6');
  if (!stockOk || stockDelta > 1) {
    c.hold(
      id: 'DG-C3.stock_refund',
      lens: 'DG6',
      severity: 'P1',
      title: 'Stock restore ×2 ou refund incoerente',
      actor: 'seller JWT',
      pre: 'devolvida ${hp.oid}',
      repro: 'PATCH devolvida + refund-order',
      expected: 'stock +0 ou +1 (não ×2); 1 refund ≤ captura',
      obtained: {
        'qty': '$qtyBefore→$qtyAfter',
        'stripe_n': stripeN,
        'stripe_sum': stripeSum,
        'paid': paidCents,
      },
    );
    c.probe(
      id: 'DG-C3.stock_refund',
      matrix: 'DG-C',
      payload: 'devolvida → refund-order Stripe TEST',
      http: rf.brief,
      bd: 'qty $qtyBefore→$qtyAfter stripe_n=$stripeN stripe_sum=$stripeSum '
          'paid=$paidCents Δb=$dBuyer Δs=$dSeller',
      result: 'HOLD',
    );
  } else {
    c.block('DG-C3.stock_refund', 'DG6', 'stock restore ≤1 + refund ≤ captura', {
      'qty': '$qtyBefore→$qtyAfter',
      'stripe': '$stripeN/$stripeSum',
    });
    c.probe(
      id: 'DG-C3.stock_refund',
      matrix: 'DG-C',
      payload: 'devolvida → refund-order Stripe TEST',
      http: rf.brief,
      bd: 'qty $qtyBefore→$qtyAfter stripe_n=$stripeN stripe_sum=$stripeSum '
          'paid=$paidCents Δb=$dBuyer Δs=$dSeller',
      result: 'FAIL',
    );
  }

  final unship = await mustPay('DG7', qty: 1);
  final buyerRf = await c.refund(unship.oid, jwt: c.buyerJwt);
  c.note('C4.buyer_refund', 'buyer refund-order', buyerRf.brief, lens: 'DG7');
  denyOrHold(
    id: 'DG-C4.buyer_refund',
    matrix: 'DG-C',
    lens: 'DG7',
    payload: 'buyer JWT POST refund-order (seller-only)',
    hit: buyerRf,
    expectedDeny: '403 Sem permissão',
    title: 'buyer refund 403',
    severity: 'P1',
  );

  final rel = await mustPay('DG7', qty: 1);
  if (!await c.toEnviado(rel.oid)) throw StateError('env rel');
  if (!await c.toConcluido(rel.oid)) throw StateError('conc rel');
  final dOpen = await c.insertDispute(orderId: rel.oid);
  final wRelA = await c.wallets();
  final relHit = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': rel.oid},
    jwt: c.buyerJwt,
  );
  final wRelB = await c.wallets();
  final dS = (wRelB['seller'] ?? 0) - (wRelA['seller'] ?? 0);
  final releasedAnyway = relHit.ok &&
      relHit.body != 'false' &&
      relHit.map?['ok'] != false &&
      dS > 0;
  c.note('C4.release_open', 'release com disputa aberta', {
    'dispute': dOpen.brief,
    'release': relHit.brief,
    'dSeller': dS,
  }, lens: 'DG7');
  if (releasedAnyway) {
    c.hold(
      id: 'DG-C4b.release_with_open_dispute',
      lens: 'DG7',
      severity: 'P0',
      title: 'Release da carteira com disputa aberta',
      actor: 'buyer JWT',
      pre: 'concluido + disputa ${dOpen.firstId}',
      repro: 'rpc batata_release_seller_wallet_for_order',
      expected: 'false / Δseller 0',
      obtained: {'hit': relHit.brief, 'dSeller': dS},
    );
    c.probe(
      id: 'DG-C4b.release_with_open_dispute',
      matrix: 'DG-C',
      payload: 'release RPC com disputa aberta',
      http: relHit.brief,
      bd: 'Δseller=$dS',
      result: 'HOLD',
    );
  } else {
    c.block('DG-C4b.release_with_open_dispute', 'DG7',
        'release bloqueado com disputa', {
      'hit': relHit.brief,
      'dSeller': dS,
    });
    c.probe(
      id: 'DG-C4b.release_with_open_dispute',
      matrix: 'DG-C',
      payload: 'release RPC com disputa aberta',
      http: relHit.brief,
      bd: 'Δseller=$dS',
      result: 'FAIL',
    );
  }

  c.note('DG.end', 'wallets fim pass1', await c.wallets(), lens: 'DG7');
  await c.dumpAll('pass1.json');
}
