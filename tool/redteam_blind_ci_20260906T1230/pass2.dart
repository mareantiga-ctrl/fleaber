/// RED TEAM CEGO CI — pass 2. Staging only. Não corrige.
/// Poço CI-A path/provas · lente CI3 · CI7 storage.
/// Matriz ≥8 NOVA (não exacto BXCC bidi / %252e%252f / ／).
import 'dart:convert';
import '_rtci.dart';

const pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

String storageSign(String buyer, String oid, String file) =>
    'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
    'order_disputes/$buyer/$oid/$file';

Future<void> main() async {
  final c = Rtci.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  c.well('CI-A');
  c.well('CI-D');

  Future<({String oid, String pid, String? pi})> ready() async {
    final paid = await c.payToPago(lens: 'CI3', initialQty: 1);
    if (paid == null) throw StateError('pay');
    if (!await c.toEnviado(paid.oid)) throw StateError('env');
    if (!await c.toConcluido(paid.oid)) throw StateError('conc');
    return paid;
  }

  final base = await ready();
  final minePath = c.disputeObj(c.buyerId!, base.oid, 'ok.png');
  await c.storageUpload(objectName: minePath, bytes: pngBytes, jwt: c.buyerJwt);
  final signed = await c.signObject(minePath, jwt: c.buyerJwt);
  c.note('CI3.signed', 'signed own proof', {'signed': signed, 'path': minePath},
      lens: 'CI3');

  final alienKey =
      'order_disputes/${c.buyer2Id}/00000000-0000-0000-0000-00000000c2c2/rtci-secret.png';
  final alienUpload = await c.storageUpload(
    objectName: alienKey,
    bytes: pngBytes,
    jwt: c.buyer2Jwt,
  );
  c.note('CI3.alien_upload', 'B2 secret object', alienUpload.brief, lens: 'CI3');

  final listAlienAsB1 = await c.storageList(
    prefix: 'order_disputes/${c.buyer2Id}/',
    jwt: c.buyerJwt,
  );
  if (listAlienAsB1.ok &&
      listAlienAsB1.body.trim().isNotEmpty &&
      listAlienAsB1.body.trim() != '[]' &&
      listAlienAsB1.body.toLowerCase().contains('rtci-secret')) {
    c.hold(
      id: 'CI7.storage_list_alien_prefix',
      lens: 'CI7',
      severity: 'P1',
      title: 'B1 lista objectos de disputa B2',
      actor: 'buyer JWT',
      pre: 'prefix order_disputes/{B2}/',
      repro: 'POST /storage/v1/object/list/fleaber_private',
      expected: '[] / 403',
      obtained: listAlienAsB1.brief,
    );
  } else {
    c.block('CI7.storage_list_alien_prefix', 'CI7', 'list prefixo B2 vazio/403',
        listAlienAsB1);
  }

  final getAlien = await c.storageGet(alienKey, jwt: c.buyerJwt);
  if (getAlien.ok && getAlien.body.contains('PNG')) {
    c.hold(
      id: 'CI7.storage_get_alien',
      lens: 'CI7',
      severity: 'P1',
      title: 'B1 GET objecto de prova B2',
      actor: 'buyer JWT',
      pre: alienKey,
      repro: 'GET object/authenticated/fleaber_private/$alienKey',
      expected: '403 / NoSuchKey',
      obtained: getAlien.brief,
    );
  } else {
    c.block('CI7.storage_get_alien', 'CI7', 'GET alheio recusado', getAlien);
  }

  // Upload traversal
  final travUpload = await c.storageUpload(
    objectName:
        'order_disputes/${c.buyerId}/${base.oid}/%25252e%25252e%25252f${c.buyer2Id}/rtci-trav.png',
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  c.note('CI3.upload_triple_encode', 'storage POST path triple-encode ../',
      travUpload.brief,
      lens: 'CI3');
  final travDot = await c.storageUpload(
    objectName:
        'order_disputes/${c.buyerId}/${base.oid}/../${c.buyer2Id}/rtci-dotdot.png',
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  c.note('CI3.upload_dotdot', 'storage POST path ASCII ../', travDot.brief,
      lens: 'CI3');
  if (travDot.ok) {
    c.hold(
      id: 'CI3.upload_dotdot_accepted',
      lens: 'CI3',
      severity: 'P1',
      title: 'Storage aceita upload com ../ no object name',
      actor: 'buyer JWT',
      pre: minePath,
      repro: 'POST object/fleaber_private/order_disputes/{me}/{oid}/../{B2}/…',
      expected: '400/403',
      obtained: travDot.brief,
    );
  } else {
    c.block('CI3.upload_dotdot', 'CI3', 'upload ../ recusado', travDot);
  }

  final clean = await c.insertDispute(orderId: base.oid);
  final did = clean.firstId;
  if (!clean.ok || did == null) {
    c.skip('CI3.clean_dispute', 'CI3', 'INSERT limpo falhou', clean);
    await c.dumpAll('pass2.json');
    return;
  }
  c.note('CI3.clean', 'disputa limpa para replies', {'did': did, 'oid': base.oid},
      lens: 'CI3');

  String needleFile(String oid) => storageSign(c.buyerId!, oid, 'ok.png');

  final probes = <Map<String, Object?>>[
    {
      'id': 'exacto.BXCC.c0ae',
      'title': 'EXACTO BXCC %c0%ae overlong . (NÃO contar)',
      'sep': '%c0%ae%c0%ae%c0%af',
      'count': false,
    },
    {
      'id': 'exacto.BXCC.pct252e',
      'title': 'EXACTO BXCC %252e%252f (NÃO contar)',
      'sep': '%252e%252e%252f',
      'count': false,
    },
    {
      'id': 'exacto.BXCC.fullwidth_slash',
      'title': 'EXACTO BXCC ／ U+FF0F (NÃO contar)',
      'sep': '\uFF0F',
      'count': false,
    },
    {
      'id': 'exacto.BXCC.bidi_rlo',
      'title': 'EXACTO BXCC RLO U+202E (NÃO contar)',
      'sep': '\u202E',
      'count': false,
    },
    {
      'id': 'exacto.BXCC.u2215',
      'title': 'EXACTO BXCC DIVISION SLASH U+2215 char (NÃO contar)',
      'sep': '\u2215',
      'count': false,
    },
    {
      'id': 'exacto.BXCC.u29f8',
      'title': 'EXACTO BXCC BIG SOLIDUS U+29F8 char (NÃO contar)',
      'sep': '\u29F8',
      'count': false,
    },
    {
      'id': 'CI3.triple_encode_dotdot',
      'title': 'proof path %25252e%25252e%25252f (triple-encode ../)',
      'sep': '%25252e%25252e%25252f',
      'count': true,
      'severity': 'P1',
    },
    {
      'id': 'CI3.pct_utf8_u2215',
      'title': 'proof path %e2%88%95 (UTF-8 DIVISION SLASH) + prefixo B2',
      'sep': '%e2%88%95',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CI3.pct_utf8_u29f8',
      'title': 'proof path %e2%a7%b8 (UTF-8 BIG SOLIDUS) + prefixo B2',
      'sep': '%e2%a7%b8',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CI3.pct_utf8_u2044',
      'title': 'proof path %e2%81%84 (UTF-8 FRACTION SLASH) + prefixo B2',
      'sep': '%e2%81%84',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CI3.pct_utf8_uff0f',
      'title': 'proof path %ef%bc%8f (UTF-8 fullwidth slash) + prefixo B2',
      'sep': '%ef%bc%8f',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CI3.null_byte',
      'title': 'proof path %00 null byte no meio do path',
      'sep': '%00',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CI3.newline_path',
      'title': r'proof path \n no path',
      'sep': '\n',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CI3.tab_path',
      'title': r'proof path \t no path',
      'sep': '\t',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CI3.zwsp_between_dots',
      'title': 'proof path . + ZWSP + . como travessia',
      'sep': '.\u200B./',
      'count': true,
      'severity': 'P1',
      'mode': 'rawsep',
    },
    {
      'id': 'CI3.soft_hyphen_dots',
      'title': 'proof path . + U+00AD + . como travessia',
      'sep': '.\u00AD./',
      'count': true,
      'severity': 'P1',
      'mode': 'rawsep',
    },
    {
      'id': 'CI3.overlong4_slash',
      'title': 'proof path %f0%80%80%af overlong 4-byte /',
      'sep': '%f0%80%80%af',
      'count': true,
      'severity': 'P1',
    },
    {
      'id': 'CI3.fw_percent_2e',
      'title': 'proof path ％2e％2e％2f (fullwidth percent U+FF05)',
      'sep': '％2e％2e％2f',
      'count': true,
      'severity': 'P1',
    },
    {
      'id': 'CI3.unicode_escape_u002e',
      'title': r'proof path %u002e%u002e%u2215 (unicode escape)',
      'sep': '%u002e%u002e%u2215',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CI3.set_minus_u2216',
      'title': 'proof path SET MINUS U+2216 + prefixo B2',
      'sep': '\u2216',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CI3.backslash_mix_raw',
      'title': r'proof path backslash ASCII mix \ + prefixo B2',
      'sep': r'\',
      'count': true,
      'severity': 'P2',
    },
  ];

  Future<void> lootOracle(String id, String stored) async {
    final getStored = await c.req('GET', stored, jwt: c.buyerJwt);
    final getAlienB1 = await c.storageGet(alienKey, jwt: c.buyerJwt);
    c.note('$id.loot', 'oráculo loot', {
      'stored_get': getStored.brief,
      'alien_get': getAlienB1.brief,
    }, lens: 'CI3');
    final loot = [getStored, getAlienB1]
        .any((h) => h.ok && h.body.contains('PNG'));
    if (loot) {
      c.hold(
        id: '$id.loot_read',
        lens: 'CI3',
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

  for (final p in probes) {
    final id = p['id'] as String;
    final title = p['title'] as String;
    final sep = p['sep'] as String;
    final count = p['count'] as bool? ?? true;
    final severity = p['severity'] as String? ?? 'P2';
    final mode = p['mode'] as String? ?? 'sep';
    final url = mode == 'rawsep'
        ? '${needleFile(base.oid)}$sep$alienKey'
        : '${needleFile(base.oid)}$sep$alienKey';
    final reply = await c.insertReply(
      disputeId: did,
      photos: [url],
      message: 'RTCI $id',
    );
    final stored = jsonEncode(reply.map?['proof_photos'] ?? []);
    final marker = sep.length > 24 ? sep.substring(0, 24) : sep;
    final persisted = reply.ok &&
        (stored.contains(sep) ||
            (marker.isNotEmpty && stored.contains(marker)));
    c.note(id, title, {
      'hit': reply.brief,
      'photos': reply.map?['proof_photos'],
      'persisted': persisted,
    }, lens: 'CI3');
    if (!count) {
      c.note('hold_residual.$id', title, {
        'hit': reply.brief,
        'persisted': persisted,
      }, lens: 'CI3');
      continue;
    }
    if (persisted) {
      c.hold(
        id: id,
        lens: 'CI3',
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
      final photos = reply.map?['proof_photos'];
      if (photos is List && photos.isNotEmpty) {
        await lootOracle(id, '${photos.first}');
      }
    } else {
      c.block(id, 'CI3', title, reply);
    }
  }

  // Relativo vs absoluto · bucket swap · public object
  Future<void> probeUrl({
    required String id,
    required String title,
    required String url,
    String severity = 'P2',
  }) async {
    final reply = await c.insertReply(
      disputeId: did,
      photos: [url],
      message: 'RTCI $id',
    );
    c.note(id, title, {
      'hit': reply.brief,
      'photos': reply.map?['proof_photos'],
    }, lens: 'CI3');
    if (reply.ok) {
      c.hold(
        id: id,
        lens: 'CI3',
        severity: severity,
        title: title,
        actor: 'buyer JWT',
        pre: 'reply $did',
        repro: 'POST proof_photos=[$url]',
        expected: 'dispute_proof_url_denied',
        obtained: reply.brief,
      );
    } else {
      c.block(id, 'CI3', title, reply);
    }
  }

  await probeUrl(
    id: 'CI3.relative_path',
    title: 'proof path relativo (sem host) order_disputes/{B1}/{oid}/ok.png',
    url: 'order_disputes/${c.buyerId}/${base.oid}/ok.png',
    severity: 'P2',
  );
  await probeUrl(
    id: 'CI3.absolute_file',
    title: 'proof path file:// absoluto',
    url: 'file:///etc/passwd',
    severity: 'P2',
  );
  await probeUrl(
    id: 'CI3.bucket_swap_public',
    title: 'proof URL bucket público /object/public/',
    url:
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/fleaber_private/order_disputes/${c.buyerId}/${base.oid}/ok.png',
    severity: 'P1',
  );
  await probeUrl(
    id: 'CI3.bucket_swap_other',
    title: 'proof URL bucket fleaber (não fleaber_private)',
    url:
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber/order_disputes/${c.buyerId}/${base.oid}/ok.png',
    severity: 'P1',
  );
  await probeUrl(
    id: 'CI3.host_confusion',
    title: 'proof host supabase.co.evil.com com needle no path',
    url:
        'https://fxdknzrqjenzqcvnwqqq.supabase.co.evil.example/storage/v1/object/sign/fleaber_private/order_disputes/${c.buyerId}/${base.oid}/ok.png',
    severity: 'P1',
  );

  // Prova de order B no dispute A (mesmo buyer, outro order)
  final other = await ready();
  final otherPath = c.disputeObj(c.buyerId!, other.oid, 'order-b.png');
  await c.storageUpload(
      objectName: otherPath, bytes: pngBytes, jwt: c.buyerJwt);
  final otherSigned = await c.signObject(otherPath, jwt: c.buyerJwt) ??
      storageSign(c.buyerId!, other.oid, 'order-b.png');
  final orderBOnA = await c.insertReply(
    disputeId: did,
    photos: [otherSigned],
    message: 'RTCI prova order B na disputa A',
  );
  c.note('CI3.proof_order_b_on_a', 'URL order B colado na disputa A', {
    'hit': orderBOnA.brief,
    'photos': orderBOnA.map?['proof_photos'],
    'order_a': base.oid,
    'order_b': other.oid,
  }, lens: 'CI3');
  if (orderBOnA.ok) {
    c.hold(
      id: 'CI3.proof_order_b_on_a',
      lens: 'CI3',
      severity: 'P1',
      title: 'Prova da encomenda B aceite na disputa da encomenda A',
      actor: 'buyer JWT',
      pre: 'disputa A ${base.oid}; object B ${other.oid}',
      repro: 'POST order_dispute_replies proof_photos=signed(order B)',
      expected: 'dispute_proof_url_denied (needle A)',
      obtained: {
        'hit': orderBOnA.brief,
        'photos': orderBOnA.map?['proof_photos'],
      },
    );
  } else {
    c.block('CI3.proof_order_b_on_a', 'CI3', 'prova order B recusada em A',
        orderBOnA);
  }

  // Overwrite prova seller vs buyer
  final ownSigned = signed ?? needleFile(base.oid);
  final owSeller = await c.patchDispute(did, {
    'proof_photos': [alienKey],
  }, jwt: c.sellerJwt);
  c.note('CI3.overwrite_seller', 'seller PATCH proof_photos para path B2', {
    'hit': owSeller.brief,
    'row': await c.disputeRow(did),
  }, lens: 'CI3');
  final afterOw = await c.disputeRow(did);
  final photosNow = jsonEncode(afterOw?['proof_photos'] ?? []);
  if (owSeller.ok && photosNow.contains('rtci-secret')) {
    c.hold(
      id: 'CI3.overwrite_seller_alien',
      lens: 'CI3',
      severity: 'P1',
      title: 'Seller overwrite proof_photos com path B2',
      actor: 'seller JWT',
      pre: 'disputa $did',
      repro: 'PATCH order_disputes proof_photos=[path B2]',
      expected: 'denied / imutável',
      obtained: {
        'hit': owSeller.brief,
        'photos': afterOw?['proof_photos'],
      },
    );
  } else {
    c.block('CI3.overwrite_seller', 'CI3', 'seller overwrite recusado/ignorado',
        owSeller);
  }

  final owBuyer = await c.patchDispute(did, {
    'proof_photos': [otherSigned],
  }, jwt: c.buyerJwt);
  c.note('CI3.overwrite_buyer_order_b', 'buyer PATCH proof_photos = order B', {
    'hit': owBuyer.brief,
    'row': await c.disputeRow(did),
  }, lens: 'CI3');
  final afterBuyer = await c.disputeRow(did);
  if (owBuyer.ok &&
      jsonEncode(afterBuyer?['proof_photos'] ?? []).contains(other.oid)) {
    c.hold(
      id: 'CI3.overwrite_buyer_order_b',
      lens: 'CI3',
      severity: 'P1',
      title: 'Buyer overwrite proof_photos da disputa A com URL da order B',
      actor: 'buyer JWT',
      pre: 'disputa A $did',
      repro: 'PATCH proof_photos=signed(order B)',
      expected: 'denied',
      obtained: {
        'hit': owBuyer.brief,
        'photos': afterBuyer?['proof_photos'],
      },
    );
  } else {
    c.block('CI3.overwrite_buyer_order_b', 'CI3',
        'buyer overwrite order B recusado', owBuyer);
  }

  // INSERT disputa (não só reply) para vectores que o canónico não lista
  Future<void> probeInsert({
    required String id,
    required String title,
    required List<String> Function(String oid) photosOf,
    String severity = 'P2',
  }) async {
    final paid = await ready();
    final photos = photosOf(paid.oid);
    final hit = await c.insertDispute(orderId: paid.oid, photos: photos);
    final storedPhotos = jsonEncode(hit.map?['proof_photos'] ?? []);
    c.note(id, title, {
      'hit': hit.brief,
      'photos': hit.map?['proof_photos'],
      'oid': paid.oid,
    }, lens: 'CI3');
    final photoHit = hit.ok &&
        photos.any((p) {
          final m = p.length > 20 ? p.substring(p.length - 20) : p;
          return storedPhotos.contains(m) ||
              storedPhotos.contains('%25252e') ||
              storedPhotos.contains('%e2%88%95') ||
              storedPhotos.contains('\u200B');
        });
    if (photoHit) {
      c.hold(
        id: id,
        lens: 'CI3',
        severity: severity,
        title: title,
        actor: 'buyer JWT',
        pre: 'INSERT disputa order ${paid.oid}',
        repro: 'POST proof_photos=$photos',
        expected: '23514 denied',
        obtained: {
          'hit': hit.brief,
          'photos': hit.map?['proof_photos'],
        },
      );
    } else {
      c.block(id, 'CI3', title, hit);
    }
  }

  await probeInsert(
    id: 'CI3.insert_triple_encode',
    title: 'INSERT disputa proof_photos %25252e triple-encode',
    photosOf: (oid) => ['${needleFile(oid)}%25252e%25252e%25252f$alienKey'],
    severity: 'P1',
  );
  await probeInsert(
    id: 'CI3.insert_pct_u2215',
    title: 'INSERT disputa proof_photos %e2%88%95',
    photosOf: (oid) => ['${needleFile(oid)}%e2%88%95$alienKey'],
    severity: 'P2',
  );
  await probeInsert(
    id: 'CI3.insert_zwsp_dots',
    title: 'INSERT disputa proof_photos ZWSP entre dots',
    photosOf: (oid) => ['${needleFile(oid)}.\u200B./$alienKey'],
    severity: 'P1',
  );
  await probeInsert(
    id: 'CI3.insert_null_byte',
    title: 'INSERT disputa proof_photos %00',
    photosOf: (oid) => ['${needleFile(oid)}%00$alienKey'],
    severity: 'P2',
  );

  // Label wrap novo (não host evil exacto)
  final labPaid = await ready();
  final lab = await c.insertDispute(
    orderId: labPaid.oid,
    extra: {
      'return_label_url':
          '${needleFile(labPaid.oid)}%25252e%25252e%25252f$alienKey',
    },
  );
  c.note('CI3.label_triple_encode', 'return_label_url triple-encode', {
    'hit': lab.brief,
    'label': lab.map?['return_label_url'],
  }, lens: 'CI3');
  if (lab.ok &&
      '${lab.map?['return_label_url']}'.contains('%25252e')) {
    c.hold(
      id: 'CI3.label_triple_encode',
      lens: 'CI3',
      severity: 'P2',
      title: 'return_label_url persiste triple-encode ../',
      actor: 'buyer JWT',
      pre: 'INSERT disputa ${labPaid.oid}',
      repro: 'POST return_label_url=prefix+%25252e…+B2',
      expected: 'order_dispute_label_url_denied',
      obtained: lab.brief,
    );
  } else {
    c.block('CI3.label_triple_encode', 'CI3', 'label triple-encode recusado',
        lab);
  }

  c.note('CI3.own_signed_kept', 'signed próprio (controlo)', ownSigned,
      lens: 'CI3');
  await c.dumpAll('pass2.json');
}
