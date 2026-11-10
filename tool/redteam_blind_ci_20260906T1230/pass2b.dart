/// RED TEAM CEGO CI — pass 2b. Storage ../ vs ../../ loot. Staging only. Não corrige.
import '_rtci.dart';

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
  await c.ensureBuyer2();
  c.well('CI-A');

  final paid = await c.payToPago(lens: 'CI3', initialQty: 1);
  if (paid == null) throw StateError('pay');
  if (!await c.toEnviado(paid.oid)) throw StateError('env');
  if (!await c.toConcluido(paid.oid)) throw StateError('conc');

  Future<void> tryUpload(String id, String objectName, {String? jwt}) async {
    final hit = await c.storageUpload(
      objectName: objectName,
      bytes: pngBytes,
      jwt: jwt ?? c.buyerJwt,
    );
    c.note(id, 'upload $objectName', {
      'hit': hit.brief,
      'key': hit.map?['Key'],
    }, lens: 'CI3');
    final key = '${hit.map?['Key']}';
    final crossed = hit.ok &&
        key.contains('order_disputes/${c.buyer2Id}') &&
        !key.contains('order_disputes/${c.buyerId}');
    if (crossed) {
      c.hold(
        id: id,
        lens: 'CI3',
        severity: 'P1',
        title: 'Upload B1 escreveu no prefixo B2 via path traversal',
        actor: 'buyer JWT',
        pre: objectName,
        repro: 'POST object/fleaber_private/$objectName',
        expected: '400/403 ou key sob B1',
        obtained: hit.brief,
      );
      final getAsB2 = await c.storageGet(
        key.replaceFirst('fleaber_private/', ''),
        jwt: c.buyer2Jwt,
      );
      final getAsB1 = await c.storageGet(
        key.replaceFirst('fleaber_private/', ''),
        jwt: c.buyerJwt,
      );
      c.note('$id.get', 'GET após traversal', {
        'b1': getAsB1.brief,
        'b2': getAsB2.brief,
      }, lens: 'CI7');
      if (getAsB2.ok && getAsB2.body.contains('PNG')) {
        c.hold(
          id: '$id.loot',
          lens: 'CI7',
          severity: 'P1',
          title: 'B2 lê objecto escrito por B1 via ../ traversal',
          actor: 'buyer2 JWT',
          pre: key,
          repro: 'GET authenticated após upload ../../',
          expected: 'sem PNG',
          obtained: getAsB2.brief,
        );
      }
    } else if (hit.ok) {
      c.block(id, 'CI3', 'upload ok mas key ficou no prefixo B1', {
        'key': key,
        'hit': hit.brief,
      });
    } else {
      c.block(id, 'CI3', 'upload traversal recusado', hit);
    }
  }

  await tryUpload(
    'CI3.upload_dotdot_one',
    'order_disputes/${c.buyerId}/${paid.oid}/../${c.buyer2Id}/rtci-p2b-one.png',
  );
  await tryUpload(
    'CI3.upload_dotdot_two',
    'order_disputes/${c.buyerId}/${paid.oid}/../../${c.buyer2Id}/rtci-p2b-two.png',
  );
  await tryUpload(
    'CI3.upload_dotdot_three',
    'order_disputes/${c.buyerId}/${paid.oid}/../../../${c.buyer2Id}/rtci-p2b-three.png',
  );
  await tryUpload(
    'CI3.upload_dotdot_encoded',
    'order_disputes/${c.buyerId}/${paid.oid}/%2e%2e/%2e%2e/${c.buyer2Id}/rtci-p2b-enc.png',
  );

  await c.dumpAll('pass2b.json');
}
