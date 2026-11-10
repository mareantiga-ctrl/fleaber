/// Confirm P2: position('//' in canonical https URL) ⇒ false positivo.
/// Staging only. Não corrige.
import '_rtda.dart';

void main() async {
  final c = Rtci.fromEnv(loadEnv());
  await c.loginActors();

  const oid = '27de0758-9e80-41d8-b016-391420a2bf02';
  const did = '1b290954-baaf-4ba4-9166-6785e93aa6cb';
  final signed =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/${c.buyerId}/$oid/ok.png';
  final relative =
      '/storage/v1/object/sign/fleaber_private/order_disputes/${c.buyerId}/$oid/ok.png';
  final schemeless = 'order_disputes/${c.buyerId}/$oid/ok.png';
  final httpsOne =
      'https:/fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/${c.buyerId}/$oid/ok.png';

  Future<void> dump(String id, HttpHit h) async {
    print('$id ${h.brief}');
  }

  final canon = await c.rpc('batata_storage_url_path_canonical',
      {'p_url': signed}, service: true);
  await dump('canon.signed', canon);

  final empty = await c.rpc('batata_dispute_proof_url_ok', {
    'p_url': '',
    'p_buyer': c.buyerId,
    'p_oid': oid,
  }, service: true);
  await dump('proof.empty', empty);

  final okSigned = await c.rpc('batata_dispute_proof_url_ok', {
    'p_url': signed,
    'p_buyer': c.buyerId,
    'p_oid': oid,
  }, service: true);
  await dump('proof.signed', okSigned);

  final okRel = await c.rpc('batata_dispute_proof_url_ok', {
    'p_url': relative,
    'p_buyer': c.buyerId,
    'p_oid': oid,
  }, service: true);
  await dump('proof.relative', okRel);

  final okOne = await c.rpc('batata_dispute_proof_url_ok', {
    'p_url': httpsOne,
    'p_buyer': c.buyerId,
    'p_oid': oid,
  }, service: true);
  await dump('proof.https_one', okOne);

  final slashPos = await c.rpc('batata_storage_url_path_canonical', {
    'p_url': signed,
  }, service: true);
  final body = slashPos.body;
  print('canon.contains_double_slash=${body.contains('//')}');

  final labJwtRel = await c.patchDispute(did, {'return_label_url': relative},
      jwt: c.buyerJwt);
  await dump('label.jwt.relative', labJwtRel);

  final labSvcRel = await c.patchDispute(did, {'return_label_url': relative},
      service: true);
  await dump('label.svc.relative', labSvcRel);

  final labSvcScheme = await c.patchDispute(did, {'return_label_url': schemeless},
      service: true);
  await dump('label.svc.schemeless', labSvcScheme);

  final labSvcOne = await c.patchDispute(did, {'return_label_url': httpsOne},
      service: true);
  await dump('label.svc.https_one', labSvcOne);

  final labSvcSigned = await c.patchDispute(did, {'return_label_url': signed},
      service: true);
  await dump('label.svc.signed', labSvcSigned);

  final row = await c.disputeRow(did);
  print('dispute.return_label_url=${row?['return_label_url']}');
  print('dispute.proof_photos=${row?['proof_photos']}');

  await dumpJson('${outDir()}/confirm_slash.json', {
    'canon': canon.brief,
    'canon_has_slashslash': body.contains('//'),
    'proof_empty': empty.brief,
    'proof_signed': okSigned.brief,
    'proof_relative': okRel.brief,
    'proof_https_one': okOne.brief,
    'label_jwt_relative': labJwtRel.brief,
    'label_svc_relative': labSvcRel.brief,
    'label_svc_schemeless': labSvcScheme.brief,
    'label_svc_https_one': labSvcOne.brief,
    'label_svc_signed': labSvcSigned.brief,
    'stored_label': row?['return_label_url'],
    'stored_photos': row?['proof_photos'],
  });
}
