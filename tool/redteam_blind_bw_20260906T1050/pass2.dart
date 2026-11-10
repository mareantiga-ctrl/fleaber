/// RED TEAM CEGO BW — pass 2. Staging only. Não corrige.
/// Lentes BW3 provas · BW7 storage list prefixo alheio.
/// Exactos BQ (NÃO contar): reply signed URL needle em ?/# · ../ em proof_photos · fleaber.pt.
/// Novas: slash unicode ／ · return_label_url wrap · storage list prefixo alheio.
import 'dart:convert';
import '_rtbw.dart';

Future<void> main() async {
  final c = Rtbw.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  Future<({String oid, String pid, String? pi})> mustPay(String lens,
      {int qty = 2}) async {
    final paid = await c.payToPago(lens: lens, initialQty: qty);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  final paid = await mustPay('BW3');
  if (!await c.toEnviado(paid.oid)) {
    throw StateError('enviado failed');
  }
  if (!await c.toConcluido(paid.oid)) {
    throw StateError('concluido failed');
  }
  final d1 = await c.insertDispute(orderId: paid.oid);
  final did = d1.firstId;
  if (!d1.ok || did == null) {
    c.skip('BW3.dispute', 'BW3', 'INSERT disputa falhou', d1);
    await c.dumpAll('pass2.json');
    return;
  }
  c.note('BW3.fixture', 'disputa para provas', {
    'oid': paid.oid,
    'did': did,
    'b1': c.buyerId,
    'b2': c.buyer2Id,
  }, lens: 'BW3');

  const pngBytes = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
    0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
    0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ];

  final minePath = c.disputeObj(c.buyerId!, paid.oid, 'rtbw-ok.png');
  final upMine = await c.storageUpload(
    objectName: minePath,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  c.note('BW3.upload_mine', 'upload prova B1', upMine.brief, lens: 'BW3');

  final b2Oid = '00000000-0000-0000-0000-00000000b2b2';
  final alienPath = c.disputeObj(c.buyer2Id!, b2Oid, 'rtbw-secret.png');
  final upAlien = await c.storageUpload(
    objectName: alienPath,
    bytes: pngBytes,
    jwt: c.buyer2Jwt,
  );
  c.note('BW3.upload_b2', 'upload secreto B2 (prefixo alheio)', upAlien.brief,
      lens: 'BW3');

  final signedMine = await c.signObject(minePath, jwt: c.buyerJwt);
  final signedAlien = await c.signObject(alienPath, jwt: c.buyer2Jwt);
  c.note('BW3.signed', 'URLs assinadas', {
    'mine_ok': signedMine != null,
    'alien_ok': signedAlien != null,
  }, lens: 'BW3');

  final needle = 'order_disputes/${c.buyerId}/${paid.oid}/';
  const fw = '\uFF0F'; // fullwidth solidus ／

  Future<void> probeProof({
    required String id,
    required String title,
    required List<String> photos,
    String expected = 'denied',
    String severity = 'P2',
  }) async {
    final hit = await c.patchDispute(did, {'proof_photos': photos});
    final row = await c.disputeRow(did);
    final stored = jsonEncode(row?['proof_photos'] ?? []);
    final marker = photos.first;
    final unique = marker.contains(fw)
        ? fw
        : marker.contains('evil.example')
            ? 'evil.example'
            : marker.contains('\u2215')
                ? '\u2215'
                : marker.contains('rtbw-secret')
                    ? 'rtbw-secret'
                    : marker.length > 40
                        ? marker.substring(marker.length - 24)
                        : marker;
    final persisted = hit.ok && stored.contains(unique);
    c.note(id, title, {
      'hit': hit.brief,
      'photos': row?['proof_photos'],
    }, lens: 'BW3');
    if (expected == 'denied') {
      if (hit.ok && persisted) {
        c.hold(
          id: id,
          lens: 'BW3',
          severity: severity,
          title: title,
          actor: 'buyer JWT',
          pre: 'disputa $did order ${paid.oid}',
          repro: 'PATCH proof_photos=$photos',
          expected: '23514 dispute_proof_url_denied',
          obtained: {'hit': hit.brief, 'stored': row?['proof_photos']},
        );
      } else {
        c.block(id, 'BW3', title, hit);
      }
    } else {
      if (!hit.ok) {
        c.skip(id, 'BW3', '$title (esperado aceite, recusado)', hit);
      }
    }
  }

  // Exactos BQ — observar, NÃO contar
  if (signedAlien != null) {
    final qNeedle = '$signedAlien?x=$needle';
    final hashNeedle = '$signedAlien#$needle';
    final qHit = await c.patchDispute(did, {
      'proof_photos': [qNeedle],
    });
    c.note('exacto.BQ.query_needle', 'BQ exacto signed URL ?needle (NÃO contar)', qHit.brief,
        lens: 'BW3');
    final hHit = await c.patchDispute(did, {
      'proof_photos': [hashNeedle],
    });
    c.note('exacto.BQ.hash_needle', 'BQ exacto signed URL #needle (NÃO contar)', hHit.brief,
        lens: 'BW3');
  }
  final trav = 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      '$minePath/../../../$alienPath';
  final travHit = await c.patchDispute(did, {
    'proof_photos': [trav],
  });
  c.note('exacto.BQ.dotdot', 'BQ exacto ../ em proof_photos (NÃO contar)', travHit.brief,
      lens: 'BW3');
  final ptHit = await c.patchDispute(did, {
    'proof_photos': ['https://fleaber.pt/order_disputes/${c.buyerId}/${paid.oid}/x.png'],
  });
  c.note('exacto.BQ.fleaber_pt', 'BQ exacto fleaber.pt (NÃO contar)', ptHit.brief,
      lens: 'BW3');

  // NOVAS — unicode slash
  final uniInPath = 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/${c.buyerId}/${paid.oid}${fw}rtbw-ok.png';
  await probeProof(
    id: 'BW3.unicode_slash_replaces_ascii',
    title: 'proof_photos path com slash unicode ／ no sítio do /',
    photos: [uniInPath],
  );

  if (signedMine != null) {
    final uniAppend = '$signedMine$fw$alienPath';
    await probeProof(
      id: 'BW3.unicode_slash_append_alien',
      title: 'proof_photos URL válida + ／ + path alheio',
      photos: [uniAppend],
      severity: 'P1',
    );
  }

  final uniWrapEvil =
      'https://evil.example/x${fw}order_disputes/${c.buyerId}/${paid.oid}/file.png';
  await probeProof(
    id: 'BW3.unicode_slash_evil_host',
    title: 'proof_photos host evil + ／ + needle ASCII',
    photos: [uniWrapEvil],
  );

  final uniHostStorage =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/${c.buyerId}/${paid.oid}/ok.png${fw}../$alienPath';
  await probeProof(
    id: 'BW3.unicode_slash_then_dotdot',
    title: 'proof_photos ／ seguido de ../ path alheio',
    photos: [uniHostStorage],
    severity: 'P1',
  );

  // division slash U+2215
  const div = '\u2215';
  final divPath = 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/${c.buyerId}/${paid.oid}${div}ok.png';
  await probeProof(
    id: 'BW3.division_slash',
    title: 'proof_photos U+2215 division slash no path',
    photos: [divPath],
  );

  // return_label_url wrap (NÃO é exacto BQ — prompt pede esta nova)
  Future<void> probeLabel({
    required String id,
    required String title,
    required String url,
    String severity = 'P2',
  }) async {
    final hit = await c.patchDispute(did, {'return_label_url': url});
    final row = await c.disputeRow(did);
    final stored = '${row?['return_label_url']}';
    c.note(id, title, {'hit': hit.brief, 'stored': stored}, lens: 'BW3');
    if (hit.ok && stored == url) {
      c.hold(
        id: id,
        lens: 'BW3',
        severity: severity,
        title: title,
        actor: 'buyer JWT',
        pre: 'disputa $did',
        repro: 'PATCH return_label_url=$url',
        expected: 'denied',
        obtained: {'hit': hit.brief, 'stored': stored},
      );
    } else {
      c.block(id, 'BW3', title, hit);
    }
  }

  await probeLabel(
    id: 'BW3.label_wrap_evil_needle_in_path',
    title: 'return_label_url wrap evil.example + needle no path',
    url: 'https://evil.example/order_disputes/${c.buyerId}/${paid.oid}/phish.pdf',
  );
  await probeLabel(
    id: 'BW3.label_wrap_fleaber_app_https',
    title: 'return_label_url wrap fleaber.app/https://evil + needle',
    url:
        'https://fleaber.app/https://evil.example/order_disputes/${c.buyerId}/${paid.oid}/x',
  );
  await probeLabel(
    id: 'BW3.label_unicode_slash_wrap',
    title: 'return_label_url wrap ／ + needle ASCII',
    url: 'https://evil.example/x${fw}order_disputes/${c.buyerId}/${paid.oid}/x',
  );
  await probeLabel(
    id: 'BW3.label_query_wrap',
    title: 'return_label_url evil?needle (query deve ser cortada)',
    url:
        'https://evil.example/phish?q=order_disputes/${c.buyerId}/${paid.oid}/',
  );

  // Reply unicode (não exacto BQ query/hash)
  if (signedMine != null) {
    final replyUni = await c.insertReply(
      disputeId: did,
      photos: ['$signedMine$fw$alienPath'],
    );
    if (replyUni.ok) {
      c.hold(
        id: 'BW3.reply_unicode_slash',
        lens: 'BW3',
        severity: 'P1',
        title: 'reply proof_photos aceita signed + ／ + path alheio',
        actor: 'buyer JWT',
        pre: 'disputa $did',
        repro: 'POST order_dispute_replies proof_photos=[signed／alien]',
        expected: 'dispute_proof_url_denied',
        obtained: replyUni.brief,
      );
    } else {
      c.block('BW3.reply_unicode_slash', 'BW3', 'reply unicode slash', replyUni);
    }
  }

  // =========================================================================
  // BW7 — storage list prefixo alheio
  // =========================================================================
  final listRootB1 = await c.storageList(
    prefix: 'order_disputes/',
    jwt: c.buyerJwt,
  );
  final listB2asB1 = await c.storageList(
    prefix: 'order_disputes/${c.buyer2Id}/',
    jwt: c.buyerJwt,
  );
  final listB2asS1 = await c.storageList(
    prefix: 'order_disputes/${c.buyer2Id}/',
    jwt: c.sellerJwt,
  );
  final listAlienAsB2 = await c.storageList(
    prefix: 'order_disputes/${c.buyer2Id}/',
    jwt: c.buyer2Jwt,
  );
  final getAlienAsB1 = await c.storageGet(alienPath, jwt: c.buyerJwt);
  final getAlienAsS1 = await c.storageGet(alienPath, jwt: c.sellerJwt);

  List<dynamic> namesOf(HttpHit h) {
    if (h.json is List) {
      return (h.json as List)
          .map((e) => e is Map ? '${e['name']}' : '$e')
          .toList();
    }
    return const [];
  }

  final rootNames = namesOf(listRootB1);
  final b2asB1Names = namesOf(listB2asB1);
  final b2asS1Names = namesOf(listB2asS1);
  final leakedRoot = rootNames.any((n) => '$n'.contains('${c.buyer2Id}'));
  final leakedPrefix = b2asB1Names.any((n) => '$n'.contains('rtbw-secret')) ||
      b2asS1Names.any((n) => '$n'.contains('rtbw-secret'));
  final leakedGet = getAlienAsB1.ok || getAlienAsS1.ok;

  c.note('BW7.storage_list', 'list/get prefixo alheio', {
    'list_root_status': listRootB1.status,
    'list_root_n': rootNames.length,
    'list_b2_as_b1': listB2asB1.brief,
    'list_b2_as_s1': listB2asS1.brief,
    'list_b2_as_b2_n': namesOf(listAlienAsB2).length,
    'get_b1': getAlienAsB1.brief,
    'get_s1': getAlienAsS1.brief,
    'leaked_root': leakedRoot,
    'leaked_prefix': leakedPrefix,
    'leaked_get': leakedGet,
  }, lens: 'BW7');

  if (leakedRoot || leakedPrefix || leakedGet) {
    c.hold(
      id: 'BW7.storage_list_prefix_alheio',
      lens: 'BW7',
      severity: leakedGet ? 'P1' : 'P2',
      title: 'Storage list/get lê prefixo order_disputes de outro comprador',
      actor: 'B1/S1 JWT',
      pre: 'ficheiro em $alienPath (B2)',
      repro: 'POST object/list prefix=order_disputes/B2/ ; GET authenticated',
      expected: 'lista vazia / 400/403 no GET',
      obtained: {
        'leaked_root': leakedRoot,
        'leaked_prefix': leakedPrefix,
        'leaked_get': leakedGet,
        'root_names_sample': rootNames.take(8).toList(),
        'b2_as_b1': b2asB1Names,
        'get_b1': getAlienAsB1.brief,
        'get_s1': getAlienAsS1.brief,
      },
    );
  } else {
    c.block(
      'BW7.storage_list_prefix_alheio',
      'BW7',
      'list/get prefixo alheio recusado',
      {
        'list_b2_as_b1': listB2asB1.brief,
        'get_b1': getAlienAsB1.brief,
        'b2_own_list_n': namesOf(listAlienAsB2).length,
      },
    );
  }

  await dumpJson('${outDir()}/pass2_ids.json', {
    'oid': paid.oid,
    'pid': paid.pid,
    'did': did,
    'pi': paid.pi,
    'minePath': minePath,
    'alienPath': alienPath,
  });
  await c.dumpAll('pass2.json');
}
