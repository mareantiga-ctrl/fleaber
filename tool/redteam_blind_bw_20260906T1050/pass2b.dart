/// RED TEAM CEGO BW — pass 2b. INSERT (não PATCH) provas + label wrap.
/// PATCH 200 [] no pass 2 não prova o guarda — retestar no INSERT.
import 'dart:convert';
import '_rtbw.dart';

Future<void> main() async {
  final c = Rtbw.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  const fw = '\uFF0F';
  const pngBytes = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
    0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
    0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ];

  Future<({String oid, String pid, String? pi, String did})> ready() async {
    final paid = await c.payToPago(lens: 'BW3', initialQty: 1);
    if (paid == null) throw StateError('pay');
    if (!await c.toEnviado(paid.oid)) throw StateError('env');
    if (!await c.toConcluido(paid.oid)) throw StateError('conc');
    return (oid: paid.oid, pid: paid.pid, pi: paid.pi, did: '');
  }

  // Observar reply pass2 — path vs query
  final oldReply = await c.rest(
    'GET',
    'order_dispute_replies?id=eq.df86f81e-f9c1-40b1-a89e-04ea6779337c&select=id,proof_photos,message',
    service: true,
  );
  final photos = oldReply.map?['proof_photos'];
  final photoStr = jsonEncode(photos);
  final qIdx = photoStr.indexOf('?');
  final fwInQuery = qIdx >= 0 && photoStr.indexOf(fw) > qIdx;
  c.note('BW3.reply_observe', 'reply pass2 photos (query vs path)', {
    'photos': photos,
    'fw_in_query': fwInQuery,
    'has_fw': photoStr.contains(fw),
  }, lens: 'BW3');
  if (fwInQuery) {
    c.note(
      'exacto.BQ.reply_query_suffix',
      '／ alheio depois de ?token= — classe BQ path-only (NÃO contar como novo P1)',
      {'fw_in_query': true},
      lens: 'BW3',
    );
  }

  final base = await ready();
  final minePath = c.disputeObj(c.buyerId!, base.oid, 'ok.png');
  await c.storageUpload(objectName: minePath, bytes: pngBytes, jwt: c.buyerJwt);
  final signed = await c.signObject(minePath, jwt: c.buyerJwt);
  final alien =
      'order_disputes/${c.buyer2Id}/00000000-0000-0000-0000-00000000b2b2/rtbw-secret.png';

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
    final marker = photos.isEmpty
        ? (label ?? '')
        : (photos.first.contains(fw)
            ? fw
            : photos.first.contains('evil.example')
                ? 'evil.example'
                : photos.first.contains('\u2215')
                    ? '\u2215'
                    : photos.first.contains('fleaber.app/https')
                        ? 'fleaber.app/https'
                        : photos.first);
    final persistedPhoto = hit.ok &&
        photos.isNotEmpty &&
        storedPhotos.contains(marker);
    final persistedLabel = hit.ok &&
        label != null &&
        storedLabel != 'null' &&
        storedLabel.contains(label.substring(0, label.length.clamp(0, 24)));
    c.note(id, title, {
      'hit': hit.brief,
      'photos': hit.map?['proof_photos'],
      'label': hit.map?['return_label_url'],
      'oid': paid.oid,
    }, lens: 'BW3');
    if (!count) {
      c.note('exacto.$id', title, hit.brief, lens: 'BW3');
      return;
    }
    if (persistedPhoto || persistedLabel) {
      c.hold(
        id: id,
        lens: 'BW3',
        severity: severity,
        title: title,
        actor: 'buyer JWT',
        pre: 'INSERT disputa order ${paid.oid}',
        repro: photos.isEmpty
            ? 'POST return_label_url=$label'
            : 'POST proof_photos=$photos',
        expected: '23514 denied / INSERT recusado',
        obtained: {
          'hit': hit.brief,
          'photos': hit.map?['proof_photos'],
          'label': hit.map?['return_label_url'],
        },
      );
    } else {
      c.block(id, 'BW3', title, hit);
    }
  }

  String storageSign(String oid, String file) =>
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/${c.buyerId}/$oid/$file';

  await probeInsert(
    id: 'BW3.insert_unicode_slash_in_path',
    title: 'INSERT proof_photos com ／ no path (antes de ?)',
    photosOf: (oid) => ['${storageSign(oid, 'ok.png')}$fw$alien'],
    severity: 'P1',
  );

  await probeInsert(
    id: 'BW3.insert_unicode_on_path_then_alien',
    title: 'INSERT signed path (sem query) + ／ + path alheio',
    photosOf: (oid) => ['${storageSign(oid, 'ok.png')}$fw$alien'],
    severity: 'P1',
  );

  await probeInsert(
    id: 'BW3.insert_unicode_evil_host',
    title: 'INSERT proof_photos evil.example／needle',
    photosOf: (oid) => [
      'https://evil.example/x${fw}order_disputes/${c.buyerId}/$oid/file.png'
    ],
  );

  await probeInsert(
    id: 'BW3.insert_label_wrap_evil_needle',
    title: 'INSERT return_label_url wrap evil + needle no path',
    photosOf: (_) => const [],
    labelOf: (oid) =>
        'https://evil.example/order_disputes/${c.buyerId}/$oid/phish.pdf',
  );

  await probeInsert(
    id: 'BW3.insert_label_wrap_app_https',
    title: 'INSERT return_label_url fleaber.app/https://evil + needle',
    photosOf: (_) => const [],
    labelOf: (oid) =>
        'https://fleaber.app/https://evil.example/order_disputes/${c.buyerId}/$oid/x',
  );

  await probeInsert(
    id: 'BW3.insert_label_unicode_wrap',
    title: 'INSERT return_label_url ／ wrap + needle',
    photosOf: (_) => const [],
    labelOf: (oid) =>
        'https://evil.example/x${fw}order_disputes/${c.buyerId}/$oid/x',
  );

  await probeInsert(
    id: 'BW3.insert_label_fleaber_pt',
    title: 'INSERT return_label_url fleaber.pt + needle (exacto BQ — não contar)',
    photosOf: (_) => const [],
    labelOf: (oid) =>
        'https://fleaber.pt/order_disputes/${c.buyerId}/$oid/label.pdf',
    count: false,
  );

  // Seller PATCH label num disputa limpa
  final forSeller = await ready();
  final dIns = await c.insertDispute(orderId: forSeller.oid);
  final did = dIns.firstId;
  if (did != null) {
    final wrap =
        'https://evil.example/order_disputes/${c.buyerId}/${forSeller.oid}/s.pdf';
    final sPatch = await c.patchDispute(did, {'return_label_url': wrap},
        jwt: c.sellerJwt);
    final row = await c.disputeRow(did);
    c.note('BW3.seller_patch_label', 'seller PATCH return_label wrap', {
      'hit': sPatch.brief,
      'stored': row?['return_label_url'],
    }, lens: 'BW3');
    if (sPatch.ok &&
        '${row?['return_label_url']}' != 'null' &&
        '${row?['return_label_url']}'.contains('evil.example')) {
      c.hold(
        id: 'BW3.seller_label_wrap',
        lens: 'BW3',
        severity: 'P2',
        title: 'Seller grava return_label_url wrap evil.example',
        actor: 'seller JWT',
        pre: 'disputa $did',
        repro: 'PATCH return_label_url=https://evil.example/…needle',
        expected: 'denied',
        obtained: {'hit': sPatch.brief, 'stored': row?['return_label_url']},
      );
    } else {
      c.block('BW3.seller_label_wrap', 'BW3', 'seller label wrap', sPatch);
    }

    final replyUrl = '${storageSign(forSeller.oid, 'ok.png')}$fw$alien';
    final reply = await c.insertReply(
      disputeId: did,
      photos: [replyUrl],
    );
      final rp = jsonEncode(reply.map?['proof_photos'] ?? []);
      c.note('BW3.reply_unicode_in_path', 'reply ／ no path sem query', {
        'hit': reply.brief,
        'photos': reply.map?['proof_photos'],
      }, lens: 'BW3');
      if (reply.ok && rp.contains(fw)) {
        c.hold(
          id: 'BW3.reply_unicode_in_path',
          lens: 'BW3',
          severity: 'P2',
          title: 'Reply guarda ／ no path (não é query-suffix BQ)',
          actor: 'buyer JWT',
          pre: 'disputa $did',
          repro: 'POST replies proof_photos=[path／alien] sem ?',
          expected: 'denied',
          obtained: reply.brief,
        );
      } else {
        c.block('BW3.reply_unicode_in_path', 'BW3', 'reply unicode path', reply);
      }
  }

  await c.dumpAll('pass2b.json');
}
