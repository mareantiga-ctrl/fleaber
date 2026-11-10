/// PASS 2 — verificar loot real: traversal cross-buyer, replies INSERT wrap,
/// 2.ª disputa em concluido, Edge amount oversize, B2 SELECT.
/// Exactos BK/AY não contar. Não corrigir.
import 'dart:convert';
import 'dart:io';
import '_rtbq.dart';

Future<void> main() async {
  final c = Rtbq.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  Future<({String oid, String pid, String? pi})> mustPay(
    String lens, {
    String? buyer,
    String? seller,
    int qty = 1,
  }) async {
    final paid = await c.payToPago(
      lens: lens,
      initialQty: qty,
      buyer: buyer,
      seller: seller,
    );
    if (paid == null) throw StateError('setup_paid_order $lens');
    return paid;
  }

  Future<HttpHit> storageGet(String objectPath, {String? jwt}) {
    return c.req(
      'GET',
      '/storage/v1/object/authenticated/fleaber_private/$objectPath',
      jwt: jwt,
    );
  }

  Future<HttpHit> storagePut(
    String objectPath,
    List<int> bytes, {
    String? jwt,
  }) {
    return c.req(
      'POST',
      '/storage/v1/object/fleaber_private/$objectPath',
      jwt: jwt,
      body: bytes,
      extra: {
        'Content-Type': 'image/png',
        'x-upsert': 'true',
      },
    );
  }

  const png = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
    0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
    0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ];

  // ---- B2 order (buyer2 × seller2) with secret proof file ----
  final b2o = await mustPay('BQ3', buyer: c.buyer2Id, seller: c.seller2Id);
  await c.patchOrder(b2o.oid, {'status': 'enviado'}, jwt: c.seller2Jwt);
  await c.patchOrder(b2o.oid, {'status': 'concluido'}, jwt: c.buyer2Jwt);
  final dB2 = await c.insertDispute(
    orderId: b2o.oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
    description: 'RTBQ B2 secret dispute',
  );
  final didB2 = dB2.firstId;
  c.note('p2.b2.dispute', 'B2 disputa', dB2.brief, lens: 'BQ3');
  if (didB2 != null) c.createdDisputeIds.add(didB2);

  final secretPath =
      'order_disputes/${c.buyer2Id}/${b2o.oid}/rtbq-secret.png';
  final up = await storagePut(secretPath, png, jwt: c.buyer2Jwt);
  c.note('p2.b2.upload', 'upload secret B2', up.brief, lens: 'BQ3');

  final getB2own = await storageGet(secretPath, jwt: c.buyer2Jwt);
  final getB1cross = await storageGet(secretPath, jwt: c.buyerJwt);
  final getS1cross = await storageGet(secretPath, jwt: c.sellerJwt);
  c.note('p2.stor.direct', 'GET secret directo', {
    'b2': getB2own.status,
    'b1': getB1cross.status,
    's1': getS1cross.status,
    'b2_len': getB2own.body.length,
  }, lens: 'BQ3');

  // ---- B1 order with dispute (concluido) ----
  final b1o = await mustPay('BQ3');
  await c.patchOrder(b1o.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(b1o.oid, {'status': 'concluido'}, jwt: c.buyerJwt);
  final dB1 = await c.insertDispute(
    orderId: b1o.oid,
    description: 'RTBQ B1 disputa para wrap/traversal',
  );
  final didB1 = dB1.firstId;
  c.note('p2.b1.dispute', 'B1 disputa', dB1.brief, lens: 'BQ7');
  if (didB1 != null) c.createdDisputeIds.add(didB1);

  // BQ7 — 2.ª disputa agora que INSERT é permitido (concluido)
  if (didB1 != null) {
    final second = await c.insertDispute(
      orderId: b1o.oid,
      description: 'RTBQ segunda disputa pós-concluido',
    );
    final list = await c.disputesFor(b1o.oid);
    if (second.ok || list.length > 1) {
      c.hold(
        id: 'BQ7-03b-second-dispute-concluido',
        lens: 'BQ7',
        severity: 'P1',
        title: '2.ª disputa na mesma encomenda concluida',
        actor: 'buyer JWT',
        pre: 'já existe disputa em concluido',
        repro: 'POST order_disputes 2×',
        expected: 'unique 409',
        obtained: {'hit': second.brief, 'count': list.length},
      );
    } else {
      c.block('BQ7-03b-second-dispute-concluido', 'BQ7', '2.ª disputa concluido', {
        'hit': second.brief,
        'count': list.length,
      });
    }

    final race = await Future.wait([
      c.insertDispute(orderId: b1o.oid, description: 'race1'),
      c.insertDispute(orderId: b1o.oid, description: 'race2'),
    ]);
    final list2 = await c.disputesFor(b1o.oid);
    if (list2.length > 1) {
      c.hold(
        id: 'BQ7-04b-race-concluido',
        lens: 'BQ7',
        severity: 'P1',
        title: 'Corrida 2× POST disputa em concluido',
        actor: 'buyer JWT',
        pre: 'concluido com disputa',
        repro: 'Future.wait 2× POST',
        expected: '1 linha',
        obtained: {
          'count': list2.length,
          'hits': race.map((h) => h.brief).toList(),
        },
      );
    } else {
      c.block('BQ7-04b-race-concluido', 'BQ7', 'race concluido', {
        'count': list2.length,
        'hits': race.map((h) => h.brief).toList(),
      });
    }
  }

  // B2 SELECT disputa B1
  if (didB1 != null) {
    final b2see = await c.rest(
      'GET',
      'order_disputes?id=eq.$didB1&select=id,proof_photos,status,description',
      jwt: c.buyer2Jwt,
    );
    final leaked = b2see.ok && b2see.list.isNotEmpty;
    if (leaked) {
      c.hold(
        id: 'BQ7-09-b2-select-dispute',
        lens: 'BQ7',
        severity: 'P2',
        title: 'B2 lê disputa de B1',
        actor: 'buyer2 JWT',
        pre: 'disputa B1',
        repro: 'GET order_disputes?id=eq.B1',
        expected: '[]',
        obtained: b2see.brief,
      );
    } else {
      c.block('BQ7-09-b2-select-dispute', 'BQ7', 'B2 select', b2see);
    }
  }

  // ---- BQ3 path traversal CROSS-BUYER ----
  if (didB1 != null) {
    final nMine = needle(c.buyerId!, b1o.oid);
    final minePath = proofUrl(c.buyerId!, b1o.oid, file: 'ok.png');
    final trav =
        '$minePath/../../../order_disputes/${c.buyer2Id}/${b2o.oid}/rtbq-secret.png';
    final patch = await c.patchDispute(didB1, {
      'proof_photos': [trav],
    }, jwt: c.buyerJwt);
    final row = await c.disputeRow(didB1);
    final stored = '${row?['proof_photos']}'.contains('../') &&
        '${row?['proof_photos']}'.contains('${c.buyer2Id}');
    c.note('p2.trav.store', 'guard aceita ../ cross-buyer', {
      'hit': patch.brief,
      'stored': stored,
      'photos': row?['proof_photos'],
    }, lens: 'BQ3');

    // GET literal traversal path
    final travObject =
        'order_disputes/${c.buyerId}/${b1o.oid}/ok.png/../../../order_disputes/${c.buyer2Id}/${b2o.oid}/rtbq-secret.png';
    final gLitB1 = await storageGet(travObject, jwt: c.buyerJwt);
    final gLitS1 = await storageGet(travObject, jwt: c.sellerJwt);
    final gNormB1 = await storageGet(secretPath, jwt: c.buyerJwt);
    final gNormS1 = await storageGet(secretPath, jwt: c.sellerJwt);
    c.note('p2.trav.get', 'GET traversal vs normalizado', {
      'lit_b1': '${gLitB1.status} ${gLitB1.body.length}b ${clip(gLitB1.body, 80)}',
      'lit_s1': '${gLitS1.status} ${gLitS1.body.length}b',
      'norm_b1': '${gNormB1.status} ${clip(gNormB1.body, 80)}',
      'norm_s1': '${gNormS1.status} ${clip(gNormS1.body, 80)}',
      'secret_ok_b2': getB2own.status,
    }, lens: 'BQ3');

    final stolen = (gLitB1.ok && gLitB1.body.contains('PNG')) ||
        (gLitS1.ok && gLitS1.body.contains('PNG')) ||
        (gNormB1.ok && gNormB1.body.contains('PNG')) ||
        (gNormS1.ok && gNormS1.body.contains('PNG'));
    if (stored && stolen) {
      c.hold(
        id: 'BQ3-03b-traversal-cross-buyer-loot',
        lens: 'BQ3',
        severity: 'P1',
        title: 'Traversal ../ + GET lê prova privada de B2',
        actor: 'buyer/seller JWT B1',
        pre: 'ficheiro em order_disputes/B2/oidB2/',
        repro: 'PATCH proof_photos=mine/../../../B2/secret; GET storage',
        expected: '400/403, sem PNG',
        obtained: {
          'lit_b1': gLitB1.brief,
          'norm_b1': gNormB1.brief,
        },
      );
    } else if (stored && !stolen) {
      c.note('p2.trav.nolooot', 'URL ../ gravada mas GET não entrega PNG B2', {
        'lit_b1': gLitB1.status,
        'norm_b1': gNormB1.status,
      }, lens: 'BQ3');
      // P2 hygiene already logged in pass1 as BQ3-03; confirm class
      c.hold(
        id: 'BQ3-03c-traversal-stored-no-loot',
        lens: 'BQ3',
        severity: 'P2',
        title: 'proof_photos guarda path com ../ (sem loot storage)',
        actor: 'buyer JWT',
        pre: 'needle próprio no prefixo',
        repro: 'PATCH ../ cross-buyer; GET 4xx',
        expected: 'path canonicalizado / denied',
        obtained: {
          'photos': row?['proof_photos'],
          'get_lit': gLitB1.status,
          'get_norm_b1': gNormB1.status,
        },
      );
    } else {
      c.block('BQ3-03b-traversal-cross-buyer', 'BQ3', 'traversal cross', {
        'hit': patch.brief,
        'stored': stored,
      });
    }

    // percent-encoded ..
    final enc =
        '$minePath/%2e%2e/%2e%2e/%2e%2e/order_disputes/${c.buyer2Id}/${b2o.oid}/rtbq-secret.png';
    final encHit = await c.patchDispute(didB1, {
      'proof_photos': [enc],
    }, jwt: c.buyerJwt);
    final encRow = await c.disputeRow(didB1);
    final encStored = '${encRow?['proof_photos']}'.contains('%2e');
    if (encHit.mutated && encStored) {
      c.hold(
        id: 'BQ3-08-percent-encoded-dotdot',
        lens: 'BQ3',
        severity: 'P2',
        title: 'proof_photos aceita %2e%2e (dot-dot encoded)',
        actor: 'buyer JWT',
        pre: 'needle no prefixo',
        repro: 'PATCH %2e%2e path',
        expected: 'denied',
        obtained: {'hit': encHit.brief, 'photos': encRow?['proof_photos']},
      );
    } else {
      c.block('BQ3-08-percent-encoded-dotdot', 'BQ3', '%2e%2e', {
        'hit': encHit.brief,
        'photos': encRow?['proof_photos'],
      });
    }

    // ---- replies INSERT wrap (PATCH é RLS 200 []) ----
    final otherPath = proofUrl(c.buyer2Id!, b2o.oid, file: 'rtbq-secret.png');
    final frag = '$otherPath#$nMine';
    final insFrag = await c.insertReply(
      disputeId: didB1,
      message: 'RTBQ insert fragment wrap',
      photos: [frag],
    );
    if (insFrag.ok && '${insFrag.map?['proof_photos']}'.contains('#')) {
      c.hold(
        id: 'BQ3-05b-reply-insert-fragment',
        lens: 'BQ3',
        severity: 'P1',
        title: 'INSERT reply prova: path B2 + needle B1 no fragmento #',
        actor: 'buyer JWT',
        pre: 'replies guard position(needle) no URL inteiro',
        repro: 'POST proof_photos=[storage/B2#order_disputes/B1/oid/]',
        expected: 'denied (strip # como na disputa)',
        obtained: insFrag.brief,
      );
    } else {
      c.block('BQ3-05b-reply-insert-fragment', 'BQ3', 'insert fragment', insFrag);
    }

    final qWrap = '$otherPath?q=$nMine';
    final insQ = await c.insertReply(
      disputeId: didB1,
      message: 'RTBQ insert query wrap',
      photos: [qWrap],
    );
    if (insQ.ok && '${insQ.map?['proof_photos']}'.contains('?')) {
      c.hold(
        id: 'BQ3-06b-reply-insert-query',
        lens: 'BQ3',
        severity: 'P1',
        title: 'INSERT reply prova: path B2 + needle B1 na query',
        actor: 'buyer JWT',
        pre: 'replies não strip ?',
        repro: 'POST proof_photos=[storage/B2?q=needle]',
        expected: 'denied',
        obtained: insQ.brief,
      );
    } else {
      c.block('BQ3-06b-reply-insert-query', 'BQ3', 'insert query', insQ);
    }

    final js = 'javascript:alert(1)//$nMine';
    final insJs = await c.insertReply(
      disputeId: didB1,
      message: 'RTBQ insert js',
      photos: [js],
    );
    await c.expectDenied(
      id: 'BQ3-04b-reply-insert-javascript',
      lens: 'BQ3',
      title: 'INSERT reply javascript: com needle',
      hit: insJs,
      actor: 'buyer JWT',
      pre: 'insert-guard javascript',
      repro: 'POST javascript:…//needle',
      severityIfOpen: 'P2',
    );
  }

  // ---- BQ4 amount oversize / tipos hostis numa order FRESCA pago ----
  final fresh = await mustPay('BQ4');
  final paid = numOf((await c.orderRow(fresh.oid))?['amount_paid_cents']) ?? 0;
  for (final entry in [
    ['huge', 999999],
    ['str1', '1'],
    ['arr', [1]],
    ['true', true],
    ['neg', -1],
  ]) {
    final h = await c.refundOrder(fresh.oid, extraBody: {'amount': entry[1]});
    final cents = numOf(h.map?['amount_cents']);
    final refunded = h.ok && h.map?['ok'] == true && h.map?['skipped'] != true;
    c.note('p2.amt.${entry[0]}', 'refund amount=${entry[1]}', {
      'hit': h.brief,
      'cents': cents,
      'paid': paid,
      'refunded': refunded,
    }, lens: 'BQ4');
    if (refunded) {
      // primeira que passar consome o PI — só a huge importa se cents > paid
      if (entry[0] == 'huge' && cents != null && cents > paid) {
        c.hold(
          id: 'BQ4-02b-amount-oversize',
          lens: 'BQ4',
          severity: 'P0',
          title: 'amount=999999 reembolsou mais que a captura',
          actor: 'seller JWT',
          pre: 'pago fresco',
          repro: 'POST refund-order amount=999999',
          expected: 'cap amount_paid_cents',
          obtained: {'cents': cents, 'paid': paid, 'hit': h.brief},
        );
      }
      break;
    }
  }

  // Refund com disputa aberta em concluido (não pago) — esperado blocked shipped/status
  if (didB1 != null) {
    final refDisp = await c.refundOrder(b1o.oid);
    final loot = refDisp.ok &&
        refDisp.map?['ok'] == true &&
        refDisp.map?['skipped'] != true &&
        refDisp.map?['refund_id'] != null;
    if (loot) {
      c.hold(
        id: 'BQ4-05b-refund-concluido-open-dispute',
        lens: 'BQ4',
        severity: 'P1',
        title: 'refund-order em concluido com disputa aberta',
        actor: 'seller JWT',
        pre: 'concluido + disputa + shipped_at',
        repro: 'POST refund-order',
        expected: '403 shipped/status/open_dispute',
        obtained: refDisp.brief,
      );
    } else {
      c.block('BQ4-05b-refund-concluido-open-dispute', 'BQ4',
          'refund concluido disputa', refDisp);
    }
  }

  // JWT RPC allows_seller_stripe_refund oracle
  final gate = await c.rpc('batata_order_allows_seller_stripe_refund', {
    'p_order_id': b1o.oid,
  }, jwt: c.buyerJwt);
  c.note('p2.gate.jwt', 'buyer RPC refund gate', gate.brief, lens: 'BQ4');

  final gateB2 = await c.rpc('batata_order_allows_seller_stripe_refund', {
    'p_order_id': b1o.oid,
  }, jwt: c.buyer2Jwt);
  c.note('p2.gate.b2', 'B2 RPC refund gate order B1', gateB2.brief, lens: 'BQ7');

  await c.dumpAll('pass2.json');
  stdout.writeln(
    'PASS2 done findings=${c.findings.length} blocked=${c.blocked.length} '
    'lenses=${c.lensesHit.toList()..sort()}',
  );
}
