/// RED TEAM CEGO CO — pass 2. Staging only. Não corrige.
/// CO-A ≥12 path proofs · CO-B label ≥4 · residual CDCI ≤3 · SVG/HTML.
import 'dart:convert';
import '_rtco.dart';

const pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

const svgBytes = <int>[
  0x3c, 0x73, 0x76, 0x67, 0x20, 0x78, 0x6d, 0x6c, 0x6e, 0x73, 0x3d, 0x22,
  0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x77, 0x77, 0x77, 0x2e, 0x77,
  0x33, 0x2e, 0x6f, 0x72, 0x67, 0x2f, 0x32, 0x30, 0x30, 0x30, 0x2f, 0x73,
  0x76, 0x67, 0x22, 0x3e, 0x3c, 0x74, 0x65, 0x78, 0x74, 0x3e, 0x72, 0x74,
  0x63, 0x6f, 0x3c, 0x2f, 0x74, 0x65, 0x78, 0x74, 0x3e, 0x3c, 0x2f, 0x73,
  0x76, 0x67, 0x3e,
];

const htmlBytes = <int>[
  0x3c, 0x68, 0x74, 0x6d, 0x6c, 0x3e, 0x3c, 0x62, 0x6f, 0x64, 0x79, 0x3e,
  0x72, 0x74, 0x63, 0x6f, 0x3c, 0x2f, 0x62, 0x6f, 0x64, 0x79, 0x3e, 0x3c,
  0x2f, 0x68, 0x74, 0x6d, 0x6c, 0x3e,
];

String storageSign(String buyer, String oid, String file) =>
    'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
    'order_disputes/$buyer/$oid/$file';

Future<void> main() async {
  final c = Rtci.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  c.well('CO-A');
  c.well('CO-B');

  Future<({String oid, String pid, String? pi})> ready() async {
    final paid = await c.payToPago(lens: 'CO3', initialQty: 1);
    if (paid == null) throw StateError('pay');
    if (!await c.toEnviado(paid.oid)) throw StateError('env');
    if (!await c.toConcluido(paid.oid)) throw StateError('conc');
    return paid;
  }

  final base = await ready();
  final minePath = c.disputeObj(c.buyerId!, base.oid, 'ok.png');
  await c.storageUpload(objectName: minePath, bytes: pngBytes, jwt: c.buyerJwt);
  final signed = await c.signObject(minePath, jwt: c.buyerJwt);
  c.note('CO3.signed', 'signed own proof', {'signed': signed, 'path': minePath},
      lens: 'CO3');

  final alienKey =
      'order_disputes/${c.buyer2Id}/00000000-0000-0000-0000-00000000c2c2/rtco-secret.png';
  final alienUpload = await c.storageUpload(
    objectName: alienKey,
    bytes: pngBytes,
    jwt: c.buyer2Jwt,
  );
  c.note('CO3.alien_upload', 'B2 secret object', alienUpload.brief, lens: 'CO3');

  final canonHits = <String, String>{};
  for (final sample in [
    '%255c',
    '%255c..%255c',
    '%252f%255c',
    '%u005c',
    '%c0%af%255c',
    '%2e%2e%5c',
    '%25255c',
    '%ef%bc%bc',
    '%25252e',
  ]) {
    final h = await c.rpc(
      'batata_storage_url_path_canonical',
      {'p_url': 'https://fxdknzrqjenzqcvnwqqq.supabase.co/x$sample'},
      service: true,
    );
    canonHits[sample] = h.brief;
  }
  c.note('CO3.canonical_rpc', 'RPC canonicalizer (service)', canonHits,
      lens: 'CO3');

  final clean = await c.insertDispute(orderId: base.oid);
  final did = clean.firstId;
  if (!clean.ok || did == null) {
    c.skip('CO3.clean_dispute', 'CO3', 'INSERT limpo falhou', clean);
    await c.dumpAll('pass2.json');
    return;
  }
  c.note('CO3.clean', 'disputa limpa para replies', {'did': did, 'oid': base.oid},
      lens: 'CO3');

  String needleFile(String oid) => storageSign(c.buyerId!, oid, 'ok.png');

  Future<void> lootOracle(String id, String stored) async {
    final getStored = await c.req('GET', stored, jwt: c.buyerJwt);
    final getAlienB1 = await c.storageGet(alienKey, jwt: c.buyerJwt);
    c.note('$id.loot', 'oráculo loot', {
      'stored_get': getStored.brief,
      'alien_get': getAlienB1.brief,
    }, lens: 'CO3');
    final loot = [getStored, getAlienB1]
        .any((h) => h.ok && h.body.contains('PNG'));
    if (loot) {
      c.hold(
        id: '$id.loot_read',
        lens: 'CO3',
        severity: 'P1',
        title: 'Leitura de prova B2 via URL persistido ($id)',
        actor: 'buyer JWT',
        pre: stored,
        repro: 'GET stored/alien',
        expected: 'sem bytes PNG alheios',
        obtained: {
          'stored': getStored.brief,
          'alien': getAlienB1.brief,
        },
      );
    }
  }

  Future<void> pathProbe({
    required String id,
    required String matrix,
    required String title,
    required String sep,
    required String payload,
    bool residual = false,
    String severity = 'P2',
  }) async {
    final url = '${needleFile(base.oid)}$sep$alienKey';
    final reply = await c.insertReply(
      disputeId: did,
      photos: [url],
      message: 'RTCO $id',
    );
    final stored = jsonEncode(reply.map?['proof_photos'] ?? []);
    final marker = sep.length > 24 ? sep.substring(0, 24) : sep;
    final persisted = reply.ok &&
        (stored.contains(sep) ||
            (marker.isNotEmpty && stored.contains(marker)) ||
            stored.contains('${c.buyer2Id}'));
    c.note(id, title, {
      'hit': reply.brief,
      'photos': reply.map?['proof_photos'],
      'persisted': persisted,
    }, lens: 'CO3');
    if (residual) {
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: reply.brief,
        bd: 'persisted=$persisted',
        result: persisted ? 'RESIDUAL' : 'FAIL',
      );
      return;
    }
    if (persisted) {
      c.hold(
        id: id,
        lens: 'CO3',
        severity: severity,
        title: title,
        actor: 'buyer JWT',
        pre: 'reply disputa $did order ${base.oid}',
        repro: 'POST order_dispute_replies proof_photos=[prefix+sep+B2]',
        expected: 'dispute_proof_url_denied',
        obtained: {
          'hit': reply.brief,
          'photos': reply.map?['proof_photos'],
        },
      );
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: reply.brief,
        bd: 'persisted=$persisted photos=${clip(stored, 180)}',
        result: 'HOLD',
      );
      final photos = reply.map?['proof_photos'];
      if (photos is List && photos.isNotEmpty) {
        await lootOracle(id, '${photos.first}');
      }
    } else {
      c.block(id, 'CO3', title, reply);
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: reply.brief,
        result: 'FAIL',
      );
    }
  }

  // CO-A1..A12 + extras beyond CDCI
  await pathProbe(
    id: 'CO-A1.pct255c',
    matrix: 'CO-A',
    title: r'proof path %255c (double-encoded backslash)',
    sep: '%255c',
    payload: r'%255c + prefixo B2',
  );
  await pathProbe(
    id: 'CO-A2.pct255c_dotdot',
    matrix: 'CO-A',
    title: r'proof path %255c..%255c',
    sep: '%255c..%255c',
    payload: r'%255c..%255c + prefixo B2',
  );
  await pathProbe(
    id: 'CO-A3.mixed_252f_255c',
    matrix: 'CO-A',
    title: r'proof path mixed %252f + %255c',
    sep: '%252f%255c',
    payload: r'%252f%255c + prefixo B2',
  );
  await pathProbe(
    id: 'CO-A4.pct_u005c',
    matrix: 'CO-A',
    title: r'proof path %u005c (unicode-escape backslash)',
    sep: '%u005c',
    payload: r'%u005c + prefixo B2',
    severity: 'P2',
  );
  await pathProbe(
    id: 'CO-A5.c0af_255c',
    matrix: 'CO-A',
    title: r'proof path %c0%af + %255c',
    sep: '%c0%af%255c',
    payload: r'%c0%af%255c + prefixo B2',
  );
  await pathProbe(
    id: 'CO-A6.windows_dotdot_backslash',
    matrix: 'CO-A',
    title: r'proof path Windows ..\ URL-encoded %2e%2e%5c',
    sep: '%2e%2e%5c',
    payload: r'%2e%2e%5c + prefixo B2',
  );
  await pathProbe(
    id: 'CO-A7.null_filename',
    matrix: 'CO-A',
    title: r'proof path %00 no filename',
    sep: '%00',
    payload: r'ok.png%00 + prefixo B2',
  );
  await pathProbe(
    id: 'CO-A8.newline_path',
    matrix: 'CO-A',
    title: r'proof path \n no path',
    sep: '\n',
    payload: r'\n + prefixo B2',
  );
  await pathProbe(
    id: 'CO-A9.cr_path',
    matrix: 'CO-A',
    title: r'proof path \r no path',
    sep: '\r',
    payload: r'\r + prefixo B2',
  );
  await pathProbe(
    id: 'CO-A16.triple_backslash',
    matrix: 'CO-A',
    title: r'proof path %25255c (triple-encode backslash, fora CDCI)',
    sep: '%25255c',
    payload: r'%25255c + prefixo B2',
    severity: 'P2',
  );
  await pathProbe(
    id: 'CO-A17.pct_fullwidth_backslash',
    matrix: 'CO-A',
    title: r'proof path %ef%bc%bc (UTF-8 fullwidth reverse solidus)',
    sep: '%ef%bc%bc',
    payload: r'%ef%bc%bc + prefixo B2',
    severity: 'P2',
  );
  await pathProbe(
    id: 'CO-A18.u005c_dotdot',
    matrix: 'CO-A',
    title: r'proof path %u005c..%u005c',
    sep: '%u005c..%u005c',
    payload: r'%u005c..%u005c + prefixo B2',
  );

  // Residual CDCI ≤3
  await pathProbe(
    id: 'CO-R1.triple_25252e',
    matrix: 'CO-R',
    title: r'RESIDUAL CDCI %25252e (não contar como finding novo se igual CI)',
    sep: '%25252e%25252e%25252f',
    payload: r'%25252e%25252e%25252f',
    residual: true,
  );
  await pathProbe(
    id: 'CO-R2.zwsp',
    matrix: 'CO-R',
    title: 'RESIDUAL CDCI ZWSP entre dots',
    sep: '.\u200B./',
    payload: 'ZWSP between dots',
    residual: true,
  );
  await pathProbe(
    id: 'CO-R3.pct_u002e',
    matrix: 'CO-R',
    title: r'RESIDUAL CDCI %u002e',
    sep: '%u002e%u002e%u2215',
    payload: r'%u002e%u002e%u2215',
    residual: true,
  );

  Future<void> probeUrl({
    required String id,
    required String matrix,
    required String title,
    required String url,
    required String payload,
    String severity = 'P2',
  }) async {
    final reply = await c.insertReply(
      disputeId: did,
      photos: [url],
      message: 'RTCO $id',
    );
    c.note(id, title, {
      'hit': reply.brief,
      'photos': reply.map?['proof_photos'],
    }, lens: 'CO3');
    if (reply.ok) {
      c.hold(
        id: id,
        lens: 'CO3',
        severity: severity,
        title: title,
        actor: 'buyer JWT',
        pre: 'reply $did',
        repro: 'POST proof_photos=[$url]',
        expected: 'dispute_proof_url_denied',
        obtained: reply.brief,
      );
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: reply.brief,
        result: 'HOLD',
      );
    } else {
      c.block(id, 'CO3', title, reply);
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: reply.brief,
        result: 'FAIL',
      );
    }
  }

  await probeUrl(
    id: 'CO-A10.bucket_swap_public',
    matrix: 'CO-A',
    title: 'proof URL bucket público /object/public/',
    url:
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/fleaber_private/order_disputes/${c.buyerId}/${base.oid}/ok.png',
    payload: 'object/public/fleaber_private/…',
    severity: 'P1',
  );
  await probeUrl(
    id: 'CO-A10b.bucket_swap_fleaber',
    matrix: 'CO-A',
    title: 'proof URL bucket fleaber (não fleaber_private)',
    url:
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber/order_disputes/${c.buyerId}/${base.oid}/ok.png',
    payload: 'object/sign/fleaber/…',
    severity: 'P1',
  );

  // CO-A11 SVG Content-Type
  final svgPath = c.disputeObj(c.buyerId!, base.oid, 'rtco.svg');
  final svgUp = await c.storageUpload(
    objectName: svgPath,
    bytes: svgBytes,
    jwt: c.buyerJwt,
    contentType: 'image/svg+xml',
  );
  c.note('CO-A11.svg_upload', 'storage POST image/svg+xml', {
    'hit': svgUp.brief,
    'key': svgUp.map?['Key'],
  }, lens: 'CO3');
  final svgSigned = await c.signObject(svgPath, jwt: c.buyerJwt);
  if (svgUp.ok && svgSigned != null) {
    final svgReply = await c.insertReply(
      disputeId: did,
      photos: [svgSigned],
      message: 'RTCO svg proof',
    );
    c.note('CO-A11.svg_proof', 'proof_photos signed SVG', svgReply.brief,
        lens: 'CO3');
    if (svgReply.ok) {
      c.hold(
        id: 'CO-A11.svg_as_photo',
        lens: 'CO3',
        severity: 'P2',
        title: 'Storage+disputa aceitam Content-Type image/svg+xml como foto',
        actor: 'buyer JWT',
        pre: svgPath,
        repro: 'POST object Content-Type=image/svg+xml; proof_photos=signed',
        expected: 'recusar SVG / só image/png|jpeg',
        obtained: {
          'upload': svgUp.brief,
          'reply': svgReply.brief,
        },
      );
      c.probe(
        id: 'CO-A11.svg_as_photo',
        matrix: 'CO-A',
        payload: 'Content-Type image/svg+xml + proof_photos',
        http: 'upload=${svgUp.brief} reply=${svgReply.brief}',
        result: 'HOLD',
      );
    } else {
      c.block('CO-A11.svg_as_photo', 'CO3', 'SVG recusado como proof',
          svgReply);
      c.probe(
        id: 'CO-A11.svg_as_photo',
        matrix: 'CO-A',
        payload: 'Content-Type image/svg+xml + proof_photos',
        http: 'upload=${svgUp.brief} reply=${svgReply.brief}',
        result: 'FAIL',
      );
    }
  } else {
    c.block('CO-A11.svg_upload', 'CO3', 'upload SVG recusado', svgUp);
    c.probe(
      id: 'CO-A11.svg_as_photo',
      matrix: 'CO-A',
      payload: 'Content-Type image/svg+xml upload',
      http: svgUp.brief,
      result: 'FAIL',
    );
  }

  // CO-A11b HTML Content-Type
  final htmlPath = c.disputeObj(c.buyerId!, base.oid, 'rtco.html');
  final htmlUp = await c.storageUpload(
    objectName: htmlPath,
    bytes: htmlBytes,
    jwt: c.buyerJwt,
    contentType: 'text/html',
  );
  c.note('CO-A11.html_upload', 'storage POST text/html', htmlUp.brief,
      lens: 'CO3');
  final htmlSigned = await c.signObject(htmlPath, jwt: c.buyerJwt);
  if (htmlUp.ok && htmlSigned != null) {
    final htmlReply = await c.insertReply(
      disputeId: did,
      photos: [htmlSigned],
      message: 'RTCO html proof',
    );
    if (htmlReply.ok) {
      c.hold(
        id: 'CO-A11.html_as_photo',
        lens: 'CO3',
        severity: 'P2',
        title: 'Storage+disputa aceitam Content-Type text/html como foto',
        actor: 'buyer JWT',
        pre: htmlPath,
        repro: 'POST object Content-Type=text/html; proof_photos=signed',
        expected: 'recusar HTML',
        obtained: {
          'upload': htmlUp.brief,
          'reply': htmlReply.brief,
        },
      );
      c.probe(
        id: 'CO-A11.html_as_photo',
        matrix: 'CO-A',
        payload: 'Content-Type text/html + proof_photos',
        http: 'upload=${htmlUp.brief} reply=${htmlReply.brief}',
        result: 'HOLD',
      );
    } else {
      c.block('CO-A11.html_as_photo', 'CO3', 'HTML recusado como proof',
          htmlReply);
      c.probe(
        id: 'CO-A11.html_as_photo',
        matrix: 'CO-A',
        payload: 'Content-Type text/html + proof_photos',
        http: 'upload=${htmlUp.brief} reply=${htmlReply.brief}',
        result: 'FAIL',
      );
    }
  } else {
    c.block('CO-A11.html_upload', 'CO3', 'upload HTML recusado', htmlUp);
    c.probe(
      id: 'CO-A11.html_as_photo',
      matrix: 'CO-A',
      payload: 'Content-Type text/html upload',
      http: htmlUp.brief,
      result: 'FAIL',
    );
  }

  // CO-A12 prova order B em disputa A
  final other = await ready();
  final otherPath = c.disputeObj(c.buyerId!, other.oid, 'order-b.png');
  await c.storageUpload(
      objectName: otherPath, bytes: pngBytes, jwt: c.buyerJwt);
  final otherSigned = await c.signObject(otherPath, jwt: c.buyerJwt) ??
      storageSign(c.buyerId!, other.oid, 'order-b.png');
  final orderBOnA = await c.insertReply(
    disputeId: did,
    photos: [otherSigned],
    message: 'RTCO prova order B na disputa A',
  );
  c.note('CO-A12.proof_order_b_on_a', 'URL order B colado na disputa A', {
    'hit': orderBOnA.brief,
    'order_a': base.oid,
    'order_b': other.oid,
  }, lens: 'CO3');
  if (orderBOnA.ok) {
    c.hold(
      id: 'CO-A12.proof_order_b_on_a',
      lens: 'CO3',
      severity: 'P1',
      title: 'Prova da encomenda B aceite na disputa da encomenda A',
      actor: 'buyer JWT',
      pre: 'disputa A ${base.oid}; object B ${other.oid}',
      repro: 'POST order_dispute_replies proof_photos=signed(order B)',
      expected: 'dispute_proof_url_denied',
      obtained: orderBOnA.brief,
    );
    c.probe(
      id: 'CO-A12.proof_order_b_on_a',
      matrix: 'CO-A',
      payload: 'signed URL order B na disputa A',
      http: orderBOnA.brief,
      result: 'HOLD',
    );
  } else {
    c.block('CO-A12.proof_order_b_on_a', 'CO3',
        'prova order B recusada em A', orderBOnA);
    c.probe(
      id: 'CO-A12.proof_order_b_on_a',
      matrix: 'CO-A',
      payload: 'signed URL order B na disputa A',
      http: orderBOnA.brief,
      result: 'FAIL',
    );
  }

  // overwrite seller/buyer
  final owSeller = await c.patchDispute(did, {
    'proof_photos': [alienKey],
  }, jwt: c.sellerJwt);
  final afterOw = await c.disputeRow(did);
  final photosNow = jsonEncode(afterOw?['proof_photos'] ?? []);
  c.note('CO-A12.overwrite_seller', 'seller PATCH proof_photos path B2', {
    'hit': owSeller.brief,
    'photos': afterOw?['proof_photos'],
  }, lens: 'CO3');
  if (owSeller.ok && photosNow.contains('rtco-secret')) {
    c.hold(
      id: 'CO-A12.overwrite_seller_alien',
      lens: 'CO3',
      severity: 'P1',
      title: 'Seller overwrite proof_photos com path B2',
      actor: 'seller JWT',
      pre: 'disputa $did',
      repro: 'PATCH order_disputes proof_photos=[path B2]',
      expected: 'denied',
      obtained: owSeller.brief,
    );
    c.probe(
      id: 'CO-A12.overwrite_seller',
      matrix: 'CO-A',
      payload: 'seller PATCH proof_photos=[path B2]',
      http: owSeller.brief,
      result: 'HOLD',
    );
  } else {
    c.block('CO-A12.overwrite_seller', 'CO3',
        'seller overwrite recusado', owSeller);
    c.probe(
      id: 'CO-A12.overwrite_seller',
      matrix: 'CO-A',
      payload: 'seller PATCH proof_photos=[path B2]',
      http: owSeller.brief,
      result: 'FAIL',
    );
  }

  final owBuyer = await c.patchDispute(did, {
    'proof_photos': [otherSigned],
  }, jwt: c.buyerJwt);
  final afterBuyer = await c.disputeRow(did);
  c.note('CO-A12.overwrite_buyer', 'buyer PATCH proof_photos = order B', {
    'hit': owBuyer.brief,
    'photos': afterBuyer?['proof_photos'],
  }, lens: 'CO3');
  if (owBuyer.ok &&
      jsonEncode(afterBuyer?['proof_photos'] ?? []).contains(other.oid)) {
    c.hold(
      id: 'CO-A12.overwrite_buyer_order_b',
      lens: 'CO3',
      severity: 'P1',
      title: 'Buyer overwrite proof_photos da disputa A com URL da order B',
      actor: 'buyer JWT',
      pre: 'disputa A $did',
      repro: 'PATCH proof_photos=signed(order B)',
      expected: 'denied',
      obtained: owBuyer.brief,
    );
    c.probe(
      id: 'CO-A12.overwrite_buyer',
      matrix: 'CO-A',
      payload: 'buyer PATCH proof_photos=signed(order B)',
      http: owBuyer.brief,
      result: 'HOLD',
    );
  } else {
    c.block('CO-A12.overwrite_buyer', 'CO3',
        'buyer overwrite order B recusado', owBuyer);
    c.probe(
      id: 'CO-A12.overwrite_buyer',
      matrix: 'CO-A',
      payload: 'buyer PATCH proof_photos=signed(order B)',
      http: owBuyer.brief,
      result: 'FAIL',
    );
  }

  // CO-B labels ≥4
  Future<void> labelProbe({
    required String id,
    required String title,
    required String url,
    required String payload,
  }) async {
    final paid = await ready();
    final lab = await c.insertDispute(
      orderId: paid.oid,
      extra: {'return_label_url': url.contains('{oid}')
          ? url.replaceAll('{oid}', paid.oid)
          : url},
    );
    final stored = '${lab.map?['return_label_url']}';
    c.note(id, title, {
      'hit': lab.brief,
      'label': stored,
      'oid': paid.oid,
    }, lens: 'CO3');
    if (lab.ok && stored.isNotEmpty && stored != 'null') {
      c.hold(
        id: id,
        lens: 'CO3',
        severity: 'P2',
        title: title,
        actor: 'buyer JWT',
        pre: 'INSERT disputa ${paid.oid}',
        repro: 'POST return_label_url=$payload',
        expected: 'order_dispute_label_url_denied',
        obtained: lab.brief,
      );
      c.probe(
        id: id,
        matrix: 'CO-B',
        payload: payload,
        http: lab.brief,
        bd: 'label=$stored',
        result: 'HOLD',
      );
    } else {
      c.block(id, 'CO3', title, lab);
      c.probe(
        id: id,
        matrix: 'CO-B',
        payload: payload,
        http: lab.brief,
        result: 'FAIL',
      );
    }
  }

  await labelProbe(
    id: 'CO-B1.label_pct255c',
    title: r'return_label_url com %255c + needle B2',
    url: '${needleFile('{oid}')}%255c$alienKey',
    payload: r'return_label_url prefix+%255c+B2',
  );
  await labelProbe(
    id: 'CO-B2.label_host_evil',
    title: 'return_label_url host evil.example',
    url:
        'https://fxdknzrqjenzqcvnwqqq.supabase.co.evil.example/storage/v1/object/sign/fleaber_private/order_disputes/x/y/z.png',
    payload: 'host supabase.co.evil.example',
  );
  await labelProbe(
    id: 'CO-B3.label_relative',
    title: 'return_label_url relativo (sem host)',
    url: 'order_disputes/{oid}/label.pdf',
    payload: 'relative path sem https host',
  );
  await labelProbe(
    id: 'CO-B4.label_double_encode_novo',
    title: r'return_label_url %25255c (triple backslash, novo pós-CDCI)',
    url: '${needleFile('{oid}')}%25255c$alienKey',
    payload: r'return_label_url prefix+%25255c+B2',
  );

  c.note('CO3.own_signed_kept', 'signed próprio (controlo)', signed, lens: 'CO3');
  await c.dumpAll('pass2.json');
}
