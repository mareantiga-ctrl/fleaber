/// PASS 3 — signed URL wrap em replies: loot real com token?
import 'dart:convert';
import 'dart:io';
import '_rtbq.dart';

Future<void> main() async {
  final c = Rtbq.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final paid = await c.payToPago(
    lens: 'BQ3',
    buyer: c.buyer2Id,
    seller: c.seller2Id,
    initialQty: 1,
  );
  if (paid == null) throw StateError('paid');
  await c.patchOrder(paid.oid, {'status': 'enviado'}, jwt: c.seller2Jwt);
  await c.patchOrder(paid.oid, {'status': 'concluido'}, jwt: c.buyer2Jwt);
  final d = await c.insertDispute(
    orderId: paid.oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  c.note('p3.d', 'B2 disputa', d.brief, lens: 'BQ3');

  const png = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
    0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
    0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ];
  final obj = 'order_disputes/${c.buyer2Id}/${paid.oid}/p3-secret.png';
  final up = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$obj',
    jwt: c.buyer2Jwt,
    body: png,
    extra: {'Content-Type': 'image/png', 'x-upsert': 'true'},
  );
  c.note('p3.up', 'upload', up.brief, lens: 'BQ3');

  final signed = await c.req(
    'POST',
    '/storage/v1/object/sign/fleaber_private/$obj',
    jwt: c.buyer2Jwt,
    body: {'expiresIn': 3600},
  );
  c.note('p3.sign', 'create signed', signed.brief, lens: 'BQ3');
  final signedPath = signed.map?['signedURL']?.toString() ??
      signed.map?['signedUrl']?.toString();

  final b1o = await c.payToPago(lens: 'BQ3', initialQty: 1);
  if (b1o == null) throw StateError('b1');
  await c.patchOrder(b1o.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(b1o.oid, {'status': 'concluido'}, jwt: c.buyerJwt);
  final d1 = await c.insertDispute(orderId: b1o.oid);
  final did = d1.firstId;
  c.note('p3.d1', 'B1 disputa', d1.brief, lens: 'BQ3');

  if (signedPath != null && did != null) {
    final abs = signedPath.startsWith('http')
        ? signedPath
        : 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1$signedPath';
    final nMine = needle(c.buyerId!, b1o.oid);
    final wrapped = abs.contains('?') ? '$abs&x=$nMine' : '$abs?x=$nMine';
    final frag = '$abs#$nMine';

    final insQ = await c.insertReply(
      disputeId: did,
      message: 'p3 signed query wrap',
      photos: [wrapped],
    );
    final insF = await c.insertReply(
      disputeId: did,
      message: 'p3 signed fragment wrap',
      photos: [frag],
    );
    c.note('p3.insQ', 'signed+query', insQ.brief, lens: 'BQ3');
    c.note('p3.insF', 'signed+#', insF.brief, lens: 'BQ3');

    // GET signed as B1 / anon / seller — token should work if stored
    final getB1 = await c.req('GET', abs, jwt: c.buyerJwt);
    final getAnon = await c.req('GET', abs);
    final getS1 = await c.req('GET', abs, jwt: c.sellerJwt);
    c.note('p3.get.signed', 'GET signed URL cross-actor', {
      'path': clip(abs, 160),
      'b1': '${getB1.status} ${getB1.body.length}b ${clip(getB1.body, 60)}',
      'anon': '${getAnon.status} ${getAnon.body.length}b',
      's1': '${getS1.status} ${getS1.body.length}b',
      'png_b1': getB1.body.contains('PNG') || getB1.body.contains('\u0089PNG'),
      'png_anon': getAnon.body.contains('PNG'),
    }, lens: 'BQ3');

    final stored = insQ.ok || insF.ok;
    final loot = getB1.ok &&
        (getB1.body.contains('PNG') || getB1.body.length > 20);
    if (stored && loot) {
      c.hold(
        id: 'BQ3-09-signed-wrap-loot',
        lens: 'BQ3',
        severity: 'P1',
        title: 'Reply aceita signed URL B2 + needle B1; GET com token lê o PNG',
        actor: 'buyer JWT (token de B2 no URL)',
        pre: 'B2 criou signed URL; B1 grava na própria disputa',
        repro: 'POST reply proof_photos=[signedB2?token&x=needle]',
        expected: 'denied (needle só no path)',
        obtained: {
          'insert_q': insQ.brief,
          'insert_f': insF.brief,
          'get_b1': '${getB1.status} ${getB1.body.length}b',
          'get_anon': '${getAnon.status} ${getAnon.body.length}b',
        },
      );
    } else if (stored && !loot) {
      c.note('p3.signed.nolooot', 'wrap gravado, GET token não entregou PNG', {
        'insQ': insQ.ok,
        'insF': insF.ok,
        'get_b1': getB1.status,
      }, lens: 'BQ3');
    }
  }

  // B2 reply na disputa B1
  if (did != null) {
    final b2r = await c.insertReply(
      disputeId: did,
      jwt: c.buyer2Jwt,
      sender: c.buyer2Id,
      message: 'B2 injecta reply',
    );
    await c.expectDenied(
      id: 'BQ7-10-b2-reply-on-b1',
      lens: 'BQ7',
      title: 'B2 escreve reply na disputa de B1',
      hit: b2r,
      actor: 'buyer2 JWT',
      pre: 'disputa B1',
      repro: 'POST order_dispute_replies JWT=B2',
      severityIfOpen: 'P1',
    );
  }

  await c.dumpAll('pass3.json');
  stdout.writeln(
    'PASS3 done findings=${c.findings.length} blocked=${c.blocked.length}',
  );
}
