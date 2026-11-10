/// Persist prova revogada numa encomenda nova. Staging, sem corrigir.
import 'dart:convert';
import 'dart:io';
import '_rtdv.dart';

const pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() async {
  final c = Rtdv.fromEnv(loadEnv());
  await c.loginActors();
  final paid = await c.payToPago(lens: 'DV2', initialQty: 1);
  if (paid == null) throw StateError('paid');
  if (!await c.toEnviado(paid.oid)) throw StateError('env');
  if (!await c.toConcluido(paid.oid)) throw StateError('conc');

  final path = c.disputeObj(c.buyerId!, paid.oid, 'gone.png');
  final up = await c.storageUpload(
    objectName: path,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final signed = await c.signObject(path, jwt: c.buyerJwt);
  final del = await c.storageDelete(path, jwt: c.buyerJwt);
  final rev = await c.revokePath(path, jwt: c.buyerJwt);
  final auth = await c.storageGet(path, jwt: c.buyerJwt);
  HttpHit cdn = HttpHit(0, 'no_sign', null);
  if (signed != null) cdn = await c.storageGetSigned(signed);

  final noQ =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$path';
  final po = await c.rpc(
    'batata_dispute_proof_url_ok',
    {'p_url': noQ, 'p_buyer': c.buyerId, 'p_oid': paid.oid},
    service: true,
  );
  final ins = await c.insertDispute(orderId: paid.oid, photos: [noQ]);
  final row = ins.firstId == null ? null : await c.disputeRow(ins.firstId!);

  final out = {
    'oid': paid.oid,
    'up': up.brief,
    'del': del.brief,
    'rev': rev.body,
    'auth': auth.brief,
    'cdn': cdn.brief,
    'proof_ok': po.body,
    'dispute': ins.brief,
    'photos': row?['proof_photos'],
    'did': ins.firstId,
  };
  await dumpJson('${outDir()}/confirm_a4_persist.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
