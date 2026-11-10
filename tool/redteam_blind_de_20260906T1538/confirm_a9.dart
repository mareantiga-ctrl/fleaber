/// Confirma A9: PATCH 200 [] vs retarget real na BD.
import 'dart:convert';
import 'dart:io';
import '_rtde.dart';

Future<void> main() async {
  final c = Rtde.fromEnv(loadEnv());
  await c.loginActors();
  final ids = jsonDecode(await File('${outDir()}/pass1_ids.json').readAsString())
      as Map<String, dynamic>;
  const followId = '7b67572d-165f-4720-a2ad-7e50f1fd0ac1';
  final s1 = ids['s1'] as String;
  final s2 = ids['s2'] as String;

  final svc = await c.rest(
    'GET',
    'follows?id=eq.$followId&select=id,follower_id,following_id',
    service: true,
  );
  final jwt = await c.rest(
    'GET',
    'follows?id=eq.$followId&select=id,follower_id,following_id',
    jwt: c.buyerJwt,
  );
  final patchAgain = await c.rest(
    'PATCH',
    'follows?id=eq.$followId',
    jwt: c.buyerJwt,
    body: {'following_id': s2},
    prefer: 'return=representation',
  );
  final after = await c.rest(
    'GET',
    'follows?id=eq.$followId&select=id,follower_id,following_id',
    service: true,
  );
  final following = after.map?['following_id']?.toString();
  final retargeted = following == s2;
  final out = {
    'svc_before_retry': svc.brief,
    'jwt_get': jwt.brief,
    'patch_retry': patchAgain.brief,
    'svc_after': after.brief,
    'following': following,
    'still_s1': following == s1,
    'retargeted_to_s2': retargeted,
    'a9_real_fail': retargeted,
  };
  await dumpJson('${outDir()}/confirm_a9.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
