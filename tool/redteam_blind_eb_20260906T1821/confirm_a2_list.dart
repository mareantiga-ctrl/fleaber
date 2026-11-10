/// Extra oráculos A2 list + unicode no meio do path. Sem corrigir.
import 'dart:io';
import '_rteb.dart';

void main() async {
  final c = Rteb.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  const oid = '30823788-8454-448c-916a-ee96efd78a9c';
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;
  const frac = '\u2044';
  const div = '\u2215';

  Future<HttpHit> ok(String url) => c.rpc(
        'batata_dispute_proof_url_ok',
        {'p_url': url, 'p_buyer': b1, 'p_oid': oid},
        service: true,
      );
  Future<HttpHit> canon(String url) =>
      c.rpc('batata_storage_url_path_canonical', {'p_url': url}, service: true);

  final listB1 = await c.storageList(prefix: 'order_disputes/$b1/', jwt: c.buyerJwt);
  final listB2 = await c.storageList(prefix: 'order_disputes/$b2/', jwt: c.buyer2Jwt);
  final listDot = await c.storageList(
    prefix: 'order_disputes/$b1/../',
    jwt: c.buyerJwt,
  );

  final midFrac =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/$b1$frac$b2/$oid/ok.png';
  final midDiv =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/$b1$div$b2/$oid/ok.png';

  final namesB1 = listB1.list
      .map((e) => e is Map ? e['name'] : e)
      .toList();
  final namesB2 = listB2.list
      .map((e) => e is Map ? e['name'] : e)
      .toList();

  final out = {
    'listB1_n': listB1.list.length,
    'listB1_has_enc': namesB1.toString().contains('rteb-enc'),
    'listB1_has_dotdot': namesB1.toString().contains('..'),
    'listB1_names': namesB1.take(20).toList(),
    'listB2_n': listB2.list.length,
    'listB2_has_enc': namesB2.toString().contains('rteb-enc'),
    'listB2_names': namesB2.take(20).toList(),
    'listDot': {'status': listDot.status, 'n': listDot.list.length, 'snip': clip(listDot.body, 180)},
    'midFrac_canon': (await canon(midFrac)).body,
    'midFrac_ok': (await ok(midFrac)).body,
    'midDiv_canon': (await canon(midDiv)).body,
    'midDiv_ok': (await ok(midDiv)).body,
  };
  await dumpJson('${outDir()}/confirm_a2_list.json', out);
  stdout.writeln(out);
}
