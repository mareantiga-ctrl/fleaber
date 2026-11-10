/// Confirm P2: label %252f simples persiste concat B2. Staging only. Não corrige.
import '_rtdg.dart';

void main() async {
  final c = Rtci.fromEnv(loadEnv());
  await c.loginActors();

  const did = 'c9b8c0e9-8664-4588-b099-859b22107770';
  const oid = '505bc24d-2664-4305-9054-4c4a177116a7';
  const stored =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/authenticated/fleaber_private/'
      'order_disputes/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/'
      '505bc24d-2664-4305-9054-4c4a177116a7/ok.png%252forder_disputes/'
      'a2f0761a-6366-4c44-855e-b7a70a923a2f/00000000-0000-0000-0000-00000000dg02/rtdg-secret.png';
  const alien =
      'order_disputes/a2f0761a-6366-4c44-855e-b7a70a923a2f/'
      '00000000-0000-0000-0000-00000000dg02/rtdg-secret.png';

  final row = await c.disputeRow(did);
  print('row.return_label_url=${row?['return_label_url']}');
  print('row.proof_photos=${row?['proof_photos']}');

  final canon = await c.rpc(
    'batata_storage_url_path_canonical',
    {'p_url': stored},
    service: true,
  );
  print('canon ${canon.brief}');

  final proof = await c.rpc(
    'batata_dispute_proof_url_ok',
    {'p_url': stored, 'p_buyer': c.buyerId, 'p_oid': oid},
    service: true,
  );
  print('proof_ok stored ${proof.brief}');

  final getStored = await c.req('GET', stored, jwt: c.buyerJwt);
  print('GET stored-as-url ${getStored.status} ${clip(getStored.body, 180)}');

  final getCanonPath = await c.storageGet(
    'order_disputes/${c.buyerId}/$oid/ok.png/order_disputes/'
    'a2f0761a-6366-4c44-855e-b7a70a923a2f/00000000-0000-0000-0000-00000000dg02/rtdg-secret.png',
    jwt: c.buyerJwt,
  );
  print('GET canon-concat-key ${getCanonPath.status} ${clip(getCanonPath.body, 180)}');

  final getAlienB1 = await c.storageGet(alien, jwt: c.buyerJwt);
  print('GET alien-as-B1 ${getAlienB1.status} ${clip(getAlienB1.body, 180)}');

  await dumpJson('${outDir()}/confirm_b5f.json', {
    'stored_row': row?['return_label_url'],
    'proof_photos': row?['proof_photos'],
    'canon': canon.brief,
    'proof_ok': proof.brief,
    'get_stored': getStored.brief,
    'get_canon_concat': getCanonPath.brief,
    'get_alien_b1': getAlienB1.brief,
  });
}
