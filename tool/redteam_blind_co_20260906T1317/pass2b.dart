/// RED TEAM CEGO CO — pass 2b. Controlo: proof URL limpo (happy path) vs 54000.
import '_rtco.dart';

const pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

Future<void> main() async {
  final c = Rtci.fromEnv(loadEnv());
  await c.loginActors();
  c.well('CO-A');

  final paid = await c.payToPago(lens: 'CO3', initialQty: 1);
  if (paid == null) throw StateError('pay');
  if (!await c.toEnviado(paid.oid)) throw StateError('env');
  if (!await c.toConcluido(paid.oid)) throw StateError('conc');

  final minePath = c.disputeObj(c.buyerId!, paid.oid, 'ok.png');
  final up = await c.storageUpload(
      objectName: minePath, bytes: pngBytes, jwt: c.buyerJwt);
  final signed = await c.signObject(minePath, jwt: c.buyerJwt);
  c.note('CO3.control.upload', 'upload png', {
    'hit': up.brief,
    'signed': signed,
  }, lens: 'CO3');

  final canonClean = await c.rpc(
    'batata_storage_url_path_canonical',
    {'p_url': signed ?? 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/x'},
    service: true,
  );
  c.note('CO3.control.canon_clean', 'canonical URL limpo', canonClean.brief,
      lens: 'CO3');

  final canonEmpty = await c.rpc(
    'batata_storage_url_path_canonical',
    {'p_url': 'https://example.com/a'},
    service: true,
  );
  c.note('CO3.control.canon_simple', 'canonical https://example.com/a',
      canonEmpty.brief,
      lens: 'CO3');

  final d = await c.insertDispute(
    orderId: paid.oid,
    photos: signed == null ? [] : [signed],
  );
  c.note('CO3.control.insert_with_photo', 'INSERT disputa proof_photos=[signed]',
      {
        'hit': d.brief,
        'photos': d.map?['proof_photos'],
      },
      lens: 'CO3');

  var did = d.firstId;
  if (did == null) {
    final d2 = await c.insertDispute(orderId: paid.oid);
    did = d2.firstId;
    c.note('CO3.control.insert_empty', 'INSERT vazio após falha com foto',
        d2.brief,
        lens: 'CO3');
  }
  if (did != null && signed != null) {
    final reply = await c.insertReply(
      disputeId: did,
      photos: [signed],
      message: 'RTCO clean signed png',
    );
    c.note('CO3.control.reply_clean', 'reply proof_photos=[signed png]',
        reply.brief,
        lens: 'CO3');
    final persisted = reply.ok &&
        jsonEncodeSafe(reply.map?['proof_photos']).contains(paid.oid);
    if (!reply.ok) {
      c.hold(
        id: 'CO-A.happy_path_proof_500',
        lens: 'CO3',
        severity: 'P2',
        title:
            'Proof URL limpo (PNG assinado próprio) recusado/500 no canonicalizer CDCI',
        actor: 'buyer JWT',
        pre: 'concluido+disputa ${paid.oid} signed PNG próprio',
        repro: 'POST order_dispute_replies proof_photos=[signed ok.png]',
        expected: '201 persistido',
        obtained: {
          'insert': d.brief,
          'reply': reply.brief,
          'canon_clean': canonClean.brief,
          'canon_simple': canonEmpty.brief,
        },
      );
      c.probe(
        id: 'CO-A.happy_path_proof_500',
        matrix: 'CO-A',
        payload: 'proof_photos=[signed PNG próprio, sem encoding]',
        http: 'insert=${d.brief} reply=${reply.brief} canon=${canonClean.brief}',
        result: 'HOLD',
      );
    } else {
      c.block('CO-A.happy_path_proof', 'CO3', 'proof limpo 201', reply);
      c.probe(
        id: 'CO-A.happy_path_proof_500',
        matrix: 'CO-A',
        payload: 'proof_photos=[signed PNG próprio, sem encoding]',
        http: reply.brief,
        bd: 'persisted=$persisted',
        result: 'FAIL',
      );
    }
  }

  await c.dumpAll('pass2b.json');
}

String jsonEncodeSafe(Object? v) {
  try {
    return '$v';
  } catch (_) {
    return '';
  }
}
