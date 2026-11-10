/// RED TEAM CEGO CU — pass 1. Staging only. Não corrige.
/// Matriz A/B/C/D ≥12 · lentes CU1–CU7 · pós-allowlist / hotfix 54000.
import 'dart:convert';
import '_rtcu.dart';

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
  c.well('CU-A');
  c.well('CU-B');
  c.well('CU-C');
  c.well('CU-D');

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
    if (has54000(hit) && matrix == 'CU-A') {
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
        result: has54000(hit) ? 'FAIL' : 'FAIL',
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

  // ---------------------------------------------------------------------------
  // Fixture HP: Stripe TEST → enviado → concluido + PNG assinado próprio
  // ---------------------------------------------------------------------------
  final hp = await mustPay('CU3', qty: 1);
  if (!await c.toEnviado(hp.oid)) throw StateError('enviado hp');
  if (!await c.toConcluido(hp.oid)) throw StateError('concluido hp');
  final minePath = c.disputeObj(c.buyerId!, hp.oid, 'ok.png');
  final up = await c.storageUpload(
    objectName: minePath,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final signed = await c.signObject(minePath, jwt: c.buyerJwt);
  c.note('CU1.upload', 'PNG próprio assinado', {
    'up': up.brief,
    'signed': signed,
    'path': minePath,
  }, lens: 'CU1');

  final alienKey =
      'order_disputes/${c.buyer2Id}/00000000-0000-0000-0000-00000000c2c2/rtcu-secret.png';
  final alienUp = await c.storageUpload(
    objectName: alienKey,
    bytes: pngBytes,
    jwt: c.buyer2Jwt,
  );
  c.note('CU4.alien', 'objecto B2', alienUp.brief, lens: 'CU4');

  String ownSign(String file) =>
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/${c.buyerId}/${hp.oid}/$file';

  // ---------------------------------------------------------------------------
  // CU-A Canonical limpo (≥3)
  // ---------------------------------------------------------------------------
  final canonSimple = await c.rpc(
    'batata_storage_url_path_canonical',
    {'p_url': 'https://example.com/a'},
    service: true,
  );
  c.note('A1.canon_simple', 'RPC https://example.com/a', canonSimple.brief,
      lens: 'CU1');
  passHappy(
    id: 'CU-A1.canon_simple',
    matrix: 'CU-A',
    lens: 'CU2',
    payload: 'RPC batata_storage_url_path_canonical https://example.com/a',
    hit: canonSimple,
    bd: has54000(canonSimple) ? '54000' : '${canonSimple.body}',
    ok: canonSimple.ok && !has54000(canonSimple),
    title: 'RPC URL limpa sem 54000',
  );

  final canonSigned = await c.rpc(
    'batata_storage_url_path_canonical',
    {
      'p_url': signed ??
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/x',
    },
    service: true,
  );
  c.note('A1.canon_signed', 'RPC signed PNG próprio', canonSigned.brief,
      lens: 'CU1');
  passHappy(
    id: 'CU-A1.canon_signed',
    matrix: 'CU-A',
    lens: 'CU2',
    payload: 'RPC canonical signed PNG próprio (https path normal)',
    hit: canonSigned,
    bd: has54000(canonSigned) ? '54000' : clip(canonSigned.body, 180),
    ok: canonSigned.ok && !has54000(canonSigned),
    title: 'RPC signed URL limpa sem 54000',
  );

  final insPhoto = await c.insertDispute(
    orderId: hp.oid,
    photos: signed == null ? [] : [signed],
  );
  c.note('A3.insert_photo', 'INSERT disputa proof canónica', {
    'hit': insPhoto.brief,
    'photos': insPhoto.map?['proof_photos'],
    'status': insPhoto.map?['status'],
  }, lens: 'CU3');
  var did = insPhoto.firstId;
  final photoOk = insPhoto.ok &&
      did != null &&
      !has54000(insPhoto) &&
      jsonEncode(insPhoto.map?['proof_photos'] ?? []).contains(hp.oid);
  passHappy(
    id: 'CU-A3.open_with_canonical_proof',
    matrix: 'CU-A',
    lens: 'CU3',
    payload: 'POST order_disputes proof_photos=[signed PNG próprio]',
    hit: insPhoto,
    bd: 'did=$did status=${insPhoto.map?['status']} photos=${clip(insPhoto.map?['proof_photos'], 160)}',
    ok: photoOk,
    title: 'Abrir disputa + prova canónica (FSM avança)',
  );

  if (did == null) {
    final empty = await c.insertDispute(orderId: hp.oid);
    did = empty.firstId;
    c.note('A3.fallback_empty', 'INSERT vazio após falha com foto', empty.brief,
        lens: 'CU3');
  }
  if (did == null) {
    c.skip('CU-A', 'CU3', 'sem disputa — abort A/C', insPhoto);
    await c.dumpAll('pass1.json');
    return;
  }

  final labelClean = await c.patchDispute(did, {
    'return_label_url': signed ?? ownSign('ok.png'),
  }, jwt: c.buyerJwt);
  c.note('A2.label_clean', 'PATCH return_label_url canónica', labelClean.brief,
      lens: 'CU1');
  passHappy(
    id: 'CU-A2.label_canonical',
    matrix: 'CU-A',
    lens: 'CU1',
    payload: 'PATCH return_label_url=signed PNG próprio https',
    hit: labelClean,
    bd: 'url=${clip(labelClean.map?['return_label_url'], 160)}',
    ok: labelClean.ok &&
        !has54000(labelClean) &&
        (labelClean.map?['return_label_url']?.toString().isNotEmpty ?? false),
    title: 'Label URL canónica limpa OK',
  );

  // ---------------------------------------------------------------------------
  // CU-B Happy path (≥3)
  // ---------------------------------------------------------------------------
  final pedido = await c.patchOrder(
    hp.oid,
    {'status': 'pedido_devolucao'},
    jwt: c.buyerJwt,
  );
  var o = await c.orderRow(hp.oid);
  c.note('B1.pedido', 'buyer pedido_devolucao', {
    'hit': pedido.brief,
    'status': o?['status'],
  }, lens: 'CU5');
  passHappy(
    id: 'CU-B1.pedido_devolucao',
    matrix: 'CU-B',
    lens: 'CU5',
    payload: 'buyer PATCH status=pedido_devolucao (order elegível + disputa)',
    hit: pedido,
    bd: 'status=${o?['status']}',
    ok: o?['status']?.toString() == 'pedido_devolucao',
    title: 'Abrir pedido_devolucao em order elegível',
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
    message: 'RTCU seller recebeu pedido de devolução.',
  );
  c.note('B2.steps', 'buyer em_devolucao + seller reply', {
    'em_dev': emDev.brief,
    'status': o?['status'],
    'seller_reply': sellerReply.brief,
  }, lens: 'CU5');
  passHappy(
    id: 'CU-B2.buyer_seller_stable',
    matrix: 'CU-B',
    lens: 'CU5',
    payload: 'buyer em_devolucao + seller reply disputa',
    hit: emDev,
    bd: 'status=${o?['status']} reply=${sellerReply.status}',
    ok: o?['status']?.toString() == 'em_devolucao' &&
        (sellerReply.ok || sellerReply.status == 201),
    title: 'Buyer+seller passos mínimos até estado estável',
  );

  // B3 medido no fim da cadeia (depois dos ataques C, para não gastar a order)

  // ---------------------------------------------------------------------------
  // CU-C Path attack ainda denied (≥4) — allowlist/canonical, não chase CDCI
  // ---------------------------------------------------------------------------
  Future<void> pathReply({
    required String id,
    required String payload,
    required String url,
    bool residual = false,
    String severity = 'P2',
    String? title,
  }) async {
    final reply = await c.insertReply(
      disputeId: did!,
      photos: [url],
      message: 'RTCU $id',
    );
    final stored = jsonEncode(reply.map?['proof_photos'] ?? []);
    final persisted = reply.ok &&
        (stored.contains(c.buyer2Id ?? 'NOB2') ||
            stored.contains('evil') ||
            stored.contains('/object/public/') ||
            stored.contains('%255c') ||
            stored.contains('..'));
    c.note(id, title ?? id, {
      'hit': reply.brief,
      'photos': reply.map?['proof_photos'],
      'persisted': persisted,
    }, lens: 'CU4');
    denyOrHold(
      id: id,
      matrix: 'CU-C',
      lens: 'CU4',
      payload: payload,
      hit: reply,
      bd: 'persisted=$persisted photos=${clip(stored, 180)}',
      expectedDeny: '403/400 dispute_proof_url_denied',
      residual: residual,
      severity: severity,
      title: title,
    );
  }

  final prefixOwn = ownSign('ok.png');
  await pathReply(
    id: 'CU-C1.pct255c_mixed',
    payload: r'%255c / mixed %252f%255c + prefixo B2',
    url: '$prefixOwn%255c..%255c$alienKey',
    title: r'proof %255c / mixed encode → deny',
  );
  await pathReply(
    id: 'CU-C1b.mixed_252f_255c',
    payload: r'%252f%255c + B2',
    url: '$prefixOwn%252f%255c$alienKey',
    title: r'proof mixed %252f%255c → deny',
  );
  await pathReply(
    id: 'CU-C2.windows_dotdot_null',
    payload: r'..\ encoded %2e%2e%5c + %00 filename',
    url: '$prefixOwn%2e%2e%5c%00$alienKey',
    title: r'proof ..\ / null %00 filename → deny',
  );
  await pathReply(
    id: 'CU-C2b.dotdot_backslash_only',
    payload: r'%2e%2e%5c traversal',
    url: '$prefixOwn%2e%2e%5c$alienKey',
    title: r'proof Windows ..\ → deny',
  );

  final bucketPublic =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/fleaber_private/'
      'order_disputes/${c.buyerId}/${hp.oid}/ok.png';
  await pathReply(
    id: 'CU-C3.bucket_swap_public',
    payload: '/object/public/fleaber_private/ + needle próprio',
    url: bucketPublic,
    title: 'bucket swap public → deny',
  );

  final signedAlien = await c.signObject(alienKey, jwt: c.buyer2Jwt);
  await pathReply(
    id: 'CU-C3b.proof_order_b_on_a',
    payload: 'signed URL order/object B2 em disputa A',
    url: signedAlien ??
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$alienKey',
    title: 'prova order B em disputa A → deny',
  );

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
    final persisted = h.ok && stored.isNotEmpty;
    c.note(id, title ?? id, {
      'hit': h.brief,
      'stored': stored,
      'persisted': persisted,
    }, lens: 'CU4');
    denyOrHold(
      id: id,
      matrix: 'CU-C',
      lens: 'CU4',
      payload: payload,
      hit: h,
      bd: 'stored=${clip(stored, 180)}',
      expectedDeny: '403 order_dispute_label_url_denied',
      residual: residual,
      severity: severity,
      title: title,
    );
  }

  await labelProbe(
    id: 'CU-C4.label_host_evil',
    payload:
        'return_label_url host supabase.co.evil.example (sem needle próprio)',
    url:
        'https://fxdknzrqjenzqcvnwqqq.supabase.co.evil.example/storage/v1/object/sign/x.png',
    title: 'label host evil → deny',
  );
  await labelProbe(
    id: 'CU-C4b.label_relative',
    payload: 'return_label_url relativo /storage/… sem host',
    url: '/storage/v1/object/sign/fleaber_private/$minePath',
    title: 'label relativo hostil → deny',
  );

  // Allowlist hole: host estrangeiro MAS needle order_disputes/{buyer}/{oid}/
  await labelProbe(
    id: 'CU-C4c.label_evil_host_with_needle',
    payload:
        'https://evil.example/…/order_disputes/{buyer}/{oid}/label.png (needle + host fora)',
    url:
        'https://evil.example/cdn/order_disputes/${c.buyerId}/${hp.oid}/label.png',
    title: 'label host evil COM needle próprio (bypass allowlist?)',
    severity: 'P2',
  );

  // Residual CDCI exacto — observar, NÃO contar (≤2)
  await pathReply(
    id: 'CU-R1.triple_25252e',
    payload: r'residual CDCI %25252e%25252e%25252f',
    url: '$prefixOwn%25252e%25252e%25252f$alienKey',
    residual: true,
    title: 'residual CDCI triple-dot (não contar)',
  );
  await pathReply(
    id: 'CU-R2.zwsp_dots',
    payload: 'residual CDCI ZWSP entre dots',
    url: '$prefixOwn.${String.fromCharCode(0x200b)}.${String.fromCharCode(0x200b)}./$alienKey',
    residual: true,
    title: 'residual CDCI ZWSP (não contar)',
  );

  // ---------------------------------------------------------------------------
  // CU-D Residual FSM/refund (≥2) — 2.ª disputa / qty / buyer refund / release
  // ---------------------------------------------------------------------------
  final second = await c.insertDispute(orderId: hp.oid);
  c.note('D1.second', '2.ª disputa mesma order', second.brief, lens: 'CU5');
  denyOrHold(
    id: 'CU-D1.second_dispute',
    matrix: 'CU-D',
    lens: 'CU5',
    payload: '2.ª POST order_disputes mesma encomenda',
    hit: second,
    expectedDeny: '409 dispute_already_exists_for_order',
    title: '2.ª disputa recusada',
  );

  final qty0 = await c.patchOrder(
    hp.oid,
    {'quantity': 0},
    jwt: c.buyerJwt,
  );
  o = await c.orderRow(hp.oid);
  c.note('D1.qty0', 'PATCH quantity=0 em pedido/em_devolucao', {
    'hit': qty0.brief,
    'qty': o?['quantity'],
  }, lens: 'CU6');
  denyOrHold(
    id: 'CU-D1b.partial_qty0',
    matrix: 'CU-D',
    lens: 'CU6',
    payload: 'buyer PATCH quantity=0',
    hit: qty0,
    bd: 'qty=${o?['quantity']}',
    expectedDeny: '403 order_money_fields_immutable',
    title: 'qty parcial 0 recusada',
  );

  // B3 + D chain: avançar até devolvida → refund Stripe + stock
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
  final stockOk = (qtyAfter - qtyBefore) <= 1 &&
      (stripeN <= 1) &&
      (stripeSum <= paidCents || paidCents == 0);
  c.note('B3.stock_refund', 'happy path stock/refund', {
    'dev': dev.brief,
    'refund': rf.brief,
    'status': o?['status'],
    'qty': '$qtyBefore→$qtyMid→$qtyAfter',
    'paid': paidCents,
    'stripe_n': stripeN,
    'stripe_sum': stripeSum,
    'dBuyer': dBuyer,
    'dSeller': dSeller,
  }, lens: 'CU7');
  if (!stockOk) {
    c.hold(
      id: 'CU-B3.stock_refund',
      lens: 'CU6',
      severity: 'P1',
      title: 'Happy path stock/refund incoerente',
      actor: 'seller JWT',
      pre: 'devolvida ${hp.oid}',
      repro: 'PATCH devolvida + refund-order',
      expected: 'stock +0 ou +1; 1 refund ≤ captura; Δwallet 0',
      obtained: {
        'qty': '$qtyBefore→$qtyAfter',
        'stripe_n': stripeN,
        'stripe_sum': stripeSum,
        'paid': paidCents,
        'dBuyer': dBuyer,
        'dSeller': dSeller,
      },
    );
    c.probe(
      id: 'CU-B3.stock_refund',
      matrix: 'CU-B',
      payload: 'devolvida → refund-order Stripe TEST',
      http: rf.brief,
      bd: 'qty $qtyBefore→$qtyAfter stripe_n=$stripeN stripe_sum=$stripeSum '
          'paid=$paidCents Δb=$dBuyer Δs=$dSeller',
      result: 'HOLD',
    );
  } else {
    c.block('CU-B3.stock_refund', 'CU6', 'stock/refund coerente', {
      'qty': '$qtyBefore→$qtyAfter',
      'stripe': '$stripeN/$stripeSum',
    });
    c.probe(
      id: 'CU-B3.stock_refund',
      matrix: 'CU-B',
      payload: 'devolvida → refund-order Stripe TEST',
      http: rf.brief,
      bd: 'qty $qtyBefore→$qtyAfter stripe_n=$stripeN stripe_sum=$stripeSum '
          'paid=$paidCents Δb=$dBuyer Δs=$dSeller',
      result: 'FAIL',
    );
  }

  // D2 buyer refund Seguro hostil
  final unship = await mustPay('CU7', qty: 1);
  final buyerRf = await c.refund(unship.oid, jwt: c.buyerJwt);
  c.note('D2.buyer_refund', 'buyer refund-order', buyerRf.brief, lens: 'CU7');
  denyOrHold(
    id: 'CU-D2.buyer_refund_seguro',
    matrix: 'CU-D',
    lens: 'CU7',
    payload: 'buyer JWT POST refund-order (Seguro seller-only)',
    hit: buyerRf,
    expectedDeny: '403 Sem permissão',
    title: 'buyer refund Seguro hostil',
    severity: 'P1',
  );

  // D2 release ∥ disputa
  final rel = await mustPay('CU7', qty: 1);
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
  c.note('D2.release_open', 'release com disputa aberta', {
    'dispute': dOpen.brief,
    'release': relHit.brief,
    'dSeller': dS,
  }, lens: 'CU7');
  if (releasedAnyway) {
    c.hold(
      id: 'CU-D2.release_with_open_dispute',
      lens: 'CU7',
      severity: 'P0',
      title: 'Release da carteira com disputa aberta',
      actor: 'buyer JWT',
      pre: 'concluido + disputa ${dOpen.firstId}',
      repro: 'rpc batata_release_seller_wallet_for_order',
      expected: 'false / Δseller 0',
      obtained: {'hit': relHit.brief, 'dSeller': dS},
    );
    c.probe(
      id: 'CU-D2.release_with_open_dispute',
      matrix: 'CU-D',
      payload: 'release RPC com disputa aberta',
      http: relHit.brief,
      bd: 'Δseller=$dS',
      result: 'HOLD',
    );
  } else {
    c.block('CU-D2.release_with_open_dispute', 'CU7',
        'release bloqueado com disputa', {
      'hit': relHit.brief,
      'dSeller': dS,
    });
    c.probe(
      id: 'CU-D2.release_with_open_dispute',
      matrix: 'CU-D',
      payload: 'release RPC com disputa aberta',
      http: relHit.brief,
      bd: 'Δseller=$dS',
      result: 'FAIL',
    );
  }

  c.note('CU.end', 'wallets fim pass1', await c.wallets(), lens: 'CU7');
  await c.dumpAll('pass1.json');
}
