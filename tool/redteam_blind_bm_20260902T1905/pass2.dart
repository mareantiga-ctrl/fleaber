/// pass2 — reproduzir findings BM; notas sem verbos; URL ../; storage jpeg.
import 'dart:convert';
import 'dart:io';

import '_rtbm.dart';

Future<void> main() async {
  final c = Rtbm.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  const chatId = 'dd403563-7dc5-436b-a465-d684986024bd';
  const oid = '7fe460e8-d13b-42d3-bea2-a690cb8c0373';
  const paidOid = '54f71515-a916-4413-8959-4a30ceafe0d9';
  const paidChat = '679247b2-d7fb-46bd-a9e4-f1592f11a460';

  Future<HttpHit> card(Map<String, Object?> p, {String? chat}) => c.postMsg(
        chatId: chat ?? chatId,
        text: jsonCard(p),
      );

  Future<void> expectPersist({
    required String id,
    required String lens,
    required String severity,
    required String title,
    required HttpHit h,
    required String mustContain,
  }) async {
    final stored = h.map?['text']?.toString() ??
        (h.list.isNotEmpty ? '${(h.list.first as Map)['text']}' : '');
    if (h.ok && stored.contains(mustContain)) {
      c.hold(
        id: id,
        lens: lens,
        severity: severity,
        title: title,
        actor: 'buyer JWT',
        pre: 'pass2 repro fixtures pass1',
        repro: 'POST chat_messages / PATCH chats',
        expected: 'recusa',
        obtained: h.brief,
        evidence: {'stored': stored, 'msg_id': h.firstId},
      );
    } else {
      c.block(id, lens, 'não reproduziu', h.brief);
    }
  }

  // Notes sem confirmado/aprovado/pago
  for (final e in [
    ['clearpay', 'Clearpay 12,00 €'],
    ['shoppay', 'Shop Pay 12,00 €'],
    ['strike', 'Strike 12,00 €'],
    ['sezzle', 'Sezzle 12,00 €'],
    ['bancontact', 'Bancontact 12,00 €'],
    ['zelle2', 'Zelle 12,00 € received'],
  ]) {
    final h = await card({
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': e[1],
    });
    await expectPersist(
      id: 'P2.notes.${e[0]}',
      lens: 'BM1',
      severity: 'P1',
      title: 'notes ${e[1]}',
      h: h,
      mustContain: e[1]!,
    );
  }

  // Inbox sem verbos
  for (final e in [
    ['clearpay', 'Clearpay 12,00 €'],
    ['shoppay', 'Shop Pay 12,00 €'],
    ['strike', 'Strike 12,00 €'],
    ['zelle', 'Zelle received 12 €'],
  ]) {
    final h = await c.rest(
      'PATCH',
      'chats?id=eq.$chatId',
      jwt: c.buyerJwt,
      body: {'last_message': e[1]},
    );
    final row = await c.chatRow(chatId);
    final stored = '${row?['last_message']}';
    if (h.ok && stored == e[1]) {
      c.hold(
        id: 'P2.inbox.${e[0]}',
        lens: 'BM5',
        severity: 'P1',
        title: 'inbox ${e[1]}',
        actor: 'buyer JWT',
        pre: 'chats last_message',
        repro: 'PATCH last_message=${e[1]}',
        expected: 'chat_inbox_preview_forbidden',
        obtained: stored,
      );
    } else {
      c.block('P2.inbox.${e[0]}', 'BM5', 'inbox recusado', {
        'http': h.brief,
        'stored': stored,
      });
    }
  }

  // Seguro labels
  final lab = await card({
    'kind': 'seguro_fleaber_paid',
    'order_id': paidOid,
    'total': '5.90',
    'label': 'Clearpay 999,00 €',
  }, chat: paidChat);
  await expectPersist(
    id: 'P2.seguro-clearpay',
    lens: 'BM1',
    severity: 'P2',
    title: 'seguro label Clearpay 999',
    h: lab,
    mustContain: 'Clearpay 999,00 €',
  );

  // Traversal: persist + URI normalize + HTTP GET
  const trav =
      '$stagingHost/storage/v1/object/fleaber_private/order_proofs/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/$oid/../../../public/rtbm-stolen.jpg';
  final travHit = await card({
    'kind': 'reservation_payment_submitted',
    'order_id': oid,
    'notes': 'ok',
    'proof_url': trav,
  });
  final storedTrav = travHit.map?['text']?.toString() ?? '';
  final uri = Uri.parse(trav);
  final norm = uri.replace(path: uri.normalizePath().path);
  c.note('P2.uri-raw', 'raw path', uri.path, lens: 'BM4');
  c.note('P2.uri-norm', 'normalizePath', norm.toString(), lens: 'BM4');

  final getRaw = await c.req('GET', trav, jwt: c.buyerJwt);
  final getNorm = await c.req('GET', norm.toString(), jwt: c.buyerJwt);
  c.note('P2.get-raw', 'GET raw ../', getRaw.brief, lens: 'BM4');
  c.note('P2.get-norm', 'GET normalized', getNorm.brief, lens: 'BM4');

  if (travHit.ok && storedTrav.contains('../')) {
    c.hold(
      id: 'P2.traversal-persist',
      lens: 'BM4',
      severity: 'P1',
      title: 'proof_url com ../ persistiu; URI.normalizePath sai de order_proofs',
      actor: 'buyer JWT',
      pre: 'needle é substring no path cru',
      repro: 'POST proof_url=.../order_proofs/{b}/{oid}/../../../public/x.jpg',
      expected: 'chat_system_card_url_denied',
      obtained: {
        'msg': travHit.brief,
        'normalized': norm.toString(),
        'get_raw': getRaw.brief,
        'get_norm': getNorm.brief,
      },
    );
  } else {
    c.block('P2.traversal-persist', 'BM4', 'não reproduziu', travHit.brief);
  }

  const prefixUrl =
      '$stagingHost/storage/v1/object/fleaber_private/other/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/order_proofs/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/$oid/x.jpg';
  final pref = await card({
    'kind': 'reservation_payment_submitted',
    'order_id': oid,
    'notes': 'ok',
    'proof_url': prefixUrl,
  });
  await expectPersist(
    id: 'P2.prefix-needle',
    lens: 'BM4',
    severity: 'P1',
    title: 'needle noutro prefixo de storage',
    h: pref,
    mustContain: '/other/',
  );

  // meta extra
  final meta = await card({
    'kind': 'reservation_payment_submitted',
    'order_id': oid,
    'notes': 'ok',
    'meta': {'rail': 'Clearpay', 'amount': '12.00'},
  });
  await expectPersist(
    id: 'P2.meta',
    lens: 'BM7',
    severity: 'P3',
    title: 'chave meta extra',
    h: meta,
    mustContain: '"meta"',
  );

  // Storage jpeg
  final jpeg = <int>[
    0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
    0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9,
  ];
  final path = 'order_proofs/${c.buyerId}/$oid/rtbm.jpg';
  final up = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$path',
    jwt: c.buyerJwt,
    rawBytes: jpeg,
    extra: {'x-upsert': 'true', 'content-type': 'image/jpeg'},
    contentType: 'image/jpeg',
  );
  c.note('P2.upload-jpeg', 'upload jpeg B1', up.brief, lens: 'BM6');

  final listB2 = await c.req(
    'POST',
    '/storage/v1/object/list/fleaber_private',
    jwt: c.buyer2Jwt,
    body: {'prefix': 'order_proofs/${c.buyerId}/', 'limit': 20},
  );
  final getB2 = await c.req(
    'GET',
    '/storage/v1/object/authenticated/fleaber_private/$path',
    jwt: c.buyer2Jwt,
  );
  final upB2 = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$path',
    jwt: c.buyer2Jwt,
    rawBytes: jpeg,
    extra: {'x-upsert': 'true'},
    contentType: 'image/jpeg',
  );
  c.note('P2.list-b2', 'list B2', listB2.brief, lens: 'BM6');
  c.note('P2.get-b2', 'get B2', getB2.brief, lens: 'BM6');
  c.note('P2.up-b2', 'upload B2', upB2.brief, lens: 'BM6');
  if (listB2.ok && listB2.body.contains('rtbm.jpg')) {
    c.hold(
      id: 'P2.storage-list',
      lens: 'BM6',
      severity: 'P1',
      title: 'B2 lista jpeg de B1',
      actor: 'buyer2',
      pre: 'upload jpeg B1',
      repro: 'list prefix order_proofs/{B1}/',
      expected: '[]',
      obtained: listB2.brief,
    );
  } else {
    c.block('P2.storage-list', 'BM6', 'list B2 vazio/403', listB2.brief);
  }
  if (getB2.ok) {
    c.hold(
      id: 'P2.storage-get',
      lens: 'BM6',
      severity: 'P1',
      title: 'B2 GET jpeg B1',
      actor: 'buyer2',
      pre: 'object jpeg',
      repro: 'GET authenticated',
      expected: '403',
      obtained: getB2.brief,
    );
  } else {
    c.block('P2.storage-get', 'BM6', 'GET B2 recusado', getB2.brief);
  }
  if (upB2.ok) {
    c.hold(
      id: 'P2.storage-up',
      lens: 'BM6',
      severity: 'P1',
      title: 'B2 overwrite jpeg B1',
      actor: 'buyer2',
      pre: 'path B1',
      repro: 'POST image/jpeg no path B1',
      expected: '403',
      obtained: upB2.brief,
    );
  } else {
    c.block('P2.storage-up', 'BM6', 'upload B2 recusado', upB2.brief);
  }

  // Encoding reprodução
  const dze = '\u0405';
  final cyr = await card({
    'kind': 'reservation_payment_submitted',
    'order_id': oid,
    'notes': '${dze}hop Pay 12,00 €',
  });
  await expectPersist(
    id: 'P2.cyr-shop',
    lens: 'BM2',
    severity: 'P1',
    title: 'Ѕhop Pay notes',
    h: cyr,
    mustContain: '${dze}hop Pay',
  );

  final fw = await card({
    'kind': 'reservation_payment_submitted',
    'order_id': oid,
    'notes': 'Ｃｌｅａｒｐａｙ 12,00 €',
  });
  await expectPersist(
    id: 'P2.fw-clearpay',
    lens: 'BM2',
    severity: 'P1',
    title: 'Clearpay fullwidth notes',
    h: fw,
    mustContain: 'Ｃｌｅａｒｐａｙ',
  );

  final out = {
    'auditor': 'REDTEAM_BLIND_BM_CHAT_POS_BFBK_v1',
    'pass': 2,
    'production_touched': false,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
  };
  await dumpJson('${outDir()}/pass2.json', out);
  stdout.writeln('PASS2 FINDINGS=${c.findings.length} BLOCKED=${c.blocked.length}');
}
