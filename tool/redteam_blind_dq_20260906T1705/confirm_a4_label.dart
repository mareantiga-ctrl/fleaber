/// Confirma A4 signed reuse + D1b label actor. Staging. Não corrige.
import 'dart:convert';
import 'dart:io';
import '_rtdq.dart';

const pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() async {
  final c = Rtdq.fromEnv(loadEnv());
  await c.loginActors();

  const oid = '13937338-60c2-4cfb-92c3-e1a9f8d4529a';
  const did = 'aa6e8cf9-38a0-4dae-aa64-e103186db049';
  final b1 = c.buyerId!;
  final path = 'order_disputes/$b1/$oid/a4b.png';

  final up = await c.storageUpload(
    objectName: path,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final signed = await c.signObject(path, jwt: c.buyerJwt);
  HttpHit before = HttpHit(0, 'no', null);
  if (signed != null) before = await c.storageGetSigned(signed);
  final del = await c.storage(
    'DELETE',
    'object/fleaber_private/$path',
    jwt: c.buyerJwt,
    extra: {'Content-Type': 'application/octet-stream'},
  );
  HttpHit after = HttpHit(0, 'no', null);
  if (signed != null) after = await c.storageGetSigned(signed);
  final auth = await c.storageGet(path, jwt: c.buyerJwt);

  final signedOk = await c.signObject(
    'order_disputes/$b1/$oid/ok.png',
    jwt: c.buyerJwt,
  );
  HttpHit buyerLab = HttpHit(0, 'no', null);
  HttpHit sellerLab = HttpHit(0, 'no', null);
  if (signedOk != null) {
    buyerLab =
        await c.patchDispute(did, {'return_label_url': signedOk}, jwt: c.buyerJwt);
    sellerLab = await c.patchDispute(
        did, {'return_label_url': signedOk}, jwt: c.sellerJwt);
  }
  final row = await c.disputeRow(did);

  final out = {
    'up': up.brief,
    'signed': signed,
    'before': before.brief,
    'del': del.brief,
    'after_old_signed': after.brief,
    'after_auth': auth.brief,
    'reuse': after.ok && !after.body.toLowerCase().contains('nosuchkey'),
    'buyer_label': buyerLab.brief,
    'seller_label': sellerLab.brief,
    'stored_label': row?['return_label_url'],
  };
  await dumpJson('${outDir()}/confirm_a4_label.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
