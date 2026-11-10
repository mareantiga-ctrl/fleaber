/// REDTEAM_BLIND_BS_CHAT_POS_BLBQ_v1 — pass2. Staging only. No fixes.
import 'dart:convert';
import 'dart:io';

import '_rtbs.dart';

Future<void> main() async {
  final c = Rtbs.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  const chatId = '3f0069dd-14cd-470c-9d34-50e3b17d75f7';
  const oidA = '463c3d0b-e1bf-4dbd-8137-8ee4fddef5bd';
  const oidB = 'dd7b0688-bbce-4423-ac3c-edf852130079';
  const paidChat = 'fea2615d-3475-46c9-a42d-c4429b23ec11';
  const liveId = 'aebf7c4a-7830-4a5b-b472-d24a713435f9';
  const sku = '7be94cea-412e-4ee6-8c54-751f2d27e235';

  final proofA = 'order_proofs/${c.buyerId}/$oidA/rtbs_a.png';
  final proofB = 'order_proofs/${c.buyerId}/$oidB/rtbs_b.png';

  final upA = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$proofA',
    jwt: c.buyerJwt,
    rawBytes: png1x1,
    contentType: 'image/png',
    extra: {'x-upsert': 'true'},
  );
  final upB = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$proofB',
    jwt: c.buyerJwt,
    rawBytes: png1x1,
    contentType: 'image/png',
    extra: {'x-upsert': 'true'},
  );
  c.note('P2.upload-a', 'upload PNG A', upA.brief, lens: 'BS6');
  c.note('P2.upload-b', 'upload PNG B', upB.brief, lens: 'BS6');

  final signB = await c.req(
    'POST',
    '/storage/v1/object/sign/fleaber_private/$proofB',
    jwt: c.buyerJwt,
    body: {'expiresIn': 3600},
  );
  final signedB = signB.map?['signedURL']?.toString() ??
      signB.map?['signedUrl']?.toString() ??
      '';
  c.note('P2.sign-b', 'signed B', signB.brief, lens: 'BS4');

  Future<void> tryCard(String id, String lens, Map<String, Object?> payload,
      {String? title, String severity = 'P1'}) async {
    final h = await c.postMsg(chatId: chatId, text: jsonCard(payload));
    final persisted = h.ok && h.firstId != null;
    if (persisted) {
      c.hold(
        id: id,
        lens: lens,
        severity: severity,
        title: title ?? id,
        actor: 'buyer JWT',
        pre: 'pass2',
        repro: 'POST ${jsonEncode(payload)}',
        expected: 'denied',
        obtained: h.brief,
        evidence: {'id': h.firstId, 'payload': payload},
      );
    } else {
      c.block(id, lens, 'recusado', h.brief);
    }
  }

  String absSignedUrl(String signed) {
    if (signed.startsWith('http')) return signed;
    if (signed.startsWith('/object/')) {
      return '$stagingHost/storage/v1$signed';
    }
    if (signed.startsWith('/storage/')) return '$stagingHost$signed';
    return '$stagingHost$signed';
  }

  if (signedB.isNotEmpty) {
    final absSigned = absSignedUrl(signedB);
    c.note('P2.abs-signed', 'abs signed B', absSigned, lens: 'BS4');
    await tryCard(
      'P2.signed-own-other-order',
      'BS4',
      {
        'kind': 'reservation_payment_submitted',
        'order_id': oidA,
        'notes': 'ok',
        'proof_url': absSigned,
      },
      title: 'proof_url signed da outra encomenda própria',
    );

    final anonGet = await c.req('GET', absSigned);
    c.note('P2.anon-get-signed-b', 'anon GET signed B',
        '${anonGet.status} len=${anonGet.body.length}',
        lens: 'BS6');
  }

  final absB =
      '$stagingHost/storage/v1/object/fleaber_private/$proofB';
  await tryCard(
    'P2.unsigned-own-other-order',
    'BS4',
    {
      'kind': 'reservation_payment_submitted',
      'order_id': oidA,
      'notes': 'ok',
      'proof_url': absB,
    },
    title: 'proof_url unsigned da outra encomenda (ficheiro agora existe)',
  );

  final authB =
      '$stagingHost/storage/v1/object/authenticated/fleaber_private/$proofB';
  await tryCard(
    'P2.auth-own-other-order',
    'BS4',
    {
      'kind': 'reservation_payment_submitted',
      'order_id': oidA,
      'notes': 'ok',
      'proof_url': authB,
    },
    title: 'object/authenticated outra encomenda própria',
  );

  // GET travessia fullwidth já persistida (msg 1447)
  const fw = '．';
  final travUrl =
      '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oidA/$fw$fw/$fw$fw/order_proofs/${c.buyerId}/$oidB/rtbs_b.png';
  final getTravBuyer = await c.req('GET',
      '/storage/v1/object/authenticated/fleaber_private/order_proofs/${c.buyerId}/$oidA/$fw$fw/$fw$fw/order_proofs/${c.buyerId}/$oidB/rtbs_b.png',
      jwt: c.buyerJwt);
  final getTravAbs = await c.req('GET', travUrl, jwt: c.buyerJwt);
  c.note('P2.get-fw-auth', 'GET authenticated fullwidth dots',
      '${getTravBuyer.status} len=${getTravBuyer.body.length} ${getTravBuyer.snippet}',
      lens: 'BS4');
  c.note('P2.get-fw-abs', 'GET abs fullwidth dots',
      '${getTravAbs.status} len=${getTravAbs.body.length} ${getTravAbs.snippet}',
      lens: 'BS4');

  final getHonestB = await c.req(
    'GET',
    '/storage/v1/object/authenticated/fleaber_private/$proofB',
    jwt: c.buyerJwt,
  );
  c.note('P2.get-honest-b', 'GET prova B (mesmo buyer)',
      '${getHonestB.status} len=${getHonestB.body.length}',
      lens: 'BS6');

  final getB2 = await c.req(
    'GET',
    '/storage/v1/object/authenticated/fleaber_private/$proofB',
    jwt: c.buyer2Jwt,
  );
  if (getB2.ok && getB2.body.length >= 8) {
    c.hold(
      id: 'P2.get-cross-user',
      lens: 'BS6',
      severity: 'P1',
      title: 'B2 lê prova B1 via authenticated',
      actor: 'buyer2 JWT',
      pre: 'PNG em order_proofs/B1/oidB',
      repro: 'GET authenticated fleaber_private/$proofB',
      expected: '403/404',
      obtained: '${getB2.status} len=${getB2.body.length}',
    );
  } else {
    c.block('P2.get-cross-user', 'BS6', 'GET B2 recusado',
        '${getB2.status} ${getB2.snippet}');
  }

  final upB2 = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$proofA',
    jwt: c.buyer2Jwt,
    rawBytes: png1x1,
    contentType: 'image/png',
    extra: {'x-upsert': 'true'},
  );
  if (upB2.ok) {
    c.hold(
      id: 'P2.upload-cross-user',
      lens: 'BS6',
      severity: 'P1',
      title: 'B2 upload PNG no prefixo B1',
      actor: 'buyer2 JWT',
      pre: 'policy insert_own',
      repro: 'POST image/png order_proofs/{B1}/…',
      expected: '403',
      obtained: upB2.brief,
    );
  } else {
    c.block('P2.upload-cross-user', 'BS6', 'upload B2 recusado', upB2.brief);
  }

  final listB2 = await c.req(
    'POST',
    '/storage/v1/object/list/fleaber_private',
    jwt: c.buyer2Jwt,
    body: {'prefix': 'order_proofs/${c.buyerId}/', 'limit': 50},
  );
  final saw = listB2.body.contains('rtbs_') || listB2.body.contains(oidA);
  if (listB2.ok && saw) {
    c.hold(
      id: 'P2.list-cross-user',
      lens: 'BS6',
      severity: 'P1',
      title: 'B2 lista provas B1',
      actor: 'buyer2 JWT',
      pre: 'PNG uploaded',
      repro: 'list prefix=order_proofs/{B1}/',
      expected: '[]',
      obtained: listB2.brief,
    );
  } else {
    c.block('P2.list-cross-user', 'BS6', 'list B2 vazio/403', listB2.brief);
  }

  // unicode slash sem ASCII dots
  const fwSlash = '／';
  await tryCard(
    'P2.unicode-slash-no-dots',
    'BS4',
    {
      'kind': 'reservation_payment_submitted',
      'order_id': oidA,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oidA${fwSlash}$oidB${fwSlash}rtbs_b.png',
    },
    title: 'proof_url slash unicode sem ..',
    severity: 'P2',
  );

  // %c0%ae overlong-ish in URL (not valid utf8 in path)
  await tryCard(
    'P2.url-overlong-dot',
    'BS4',
    {
      'kind': 'reservation_payment_submitted',
      'order_id': oidA,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oidA/%c0%ae%c0%ae/%c0%ae%c0%ae/order_proofs/${c.buyerId}/$oidB/rtbs_b.png',
    },
    title: 'proof_url %c0%ae (overlong-like dots)',
  );

  // seller vê as notes? GET chat as seller
  final sellerSee = await c.rest(
    'GET',
    'chat_messages?id=eq.1417&select=id,text',
    jwt: c.sellerJwt,
  );
  c.note('P2.seller-see-payoneer', 'seller GET msg Payoneer', sellerSee.brief,
      lens: 'BS1');

  final sellerSeguro = await c.rest(
    'GET',
    'chat_messages?chat_id=eq.$paidChat&text=like.*Payoneer*&select=id,text&limit=3',
    jwt: c.sellerJwt,
  );
  c.note('P2.seller-see-seguro', 'seller GET seguro Payoneer',
      sellerSeguro.brief,
      lens: 'BS1');

  final inbox = await c.chatRow(chatId);
  c.note('P2.inbox-now', 'last_message actual', inbox?['last_message'],
      lens: 'BS5');

  final live = await c.rest(
    'GET',
    'lives?id=eq.$liveId&select=id,status,is_active',
    service: true,
  );
  final liveMap = live.map ?? {};
  if ('${liveMap['status']}' != 'ended' || liveMap['is_active'] == true) {
    await c.rest(
      'PATCH',
      'lives?id=eq.$liveId',
      service: true,
      body: {'status': 'ended', 'is_active': false},
      prefer: 'return=minimal',
    );
    c.note('P2.end-live', 'force end', live.brief, lens: 'BS8');
  } else {
    c.note('P2.live-ended', 'live já ended', live.brief, lens: 'BS8');
  }

  // product still listed? leave it; not a finding

  final out = {
    'auditor': 'REDTEAM_BLIND_BS_CHAT_POS_BLBQ_v1',
    'pass': 2,
    'sku': sku,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  };
  await dumpJson('${outDir()}/pass2.json', out);
  stdout.writeln(
      'PASS2 FINDINGS=${c.findings.length} BLOCKED=${c.blocked.length}');
}
