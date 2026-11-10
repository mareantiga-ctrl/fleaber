/// Confirm A1/A3: auth.uid vs env id; JWT visibility of S1/product.
import 'dart:convert';
import 'dart:io';
import '_rtcy.dart';

Future<void> main() async {
  final c = Rtcy.fromEnv(loadEnv());
  await c.loginActors();
  final ids = jsonDecode(await File('${outDir()}/pass1_ids.json').readAsString())
      as Map<String, dynamic>;
  final s1 = ids['s1'] as String;
  final prod = ids['prodPub'] as String;
  final b1env = c.buyerId!;

  final me = await c.req('GET', '/auth/v1/user', jwt: c.buyerJwt);
  final uid = (me.json is Map) ? (me.json as Map)['id']?.toString() : null;
  final prof = await c.rest(
    'GET',
    'profiles?id=eq.$s1&select=id,hub_published,user_type,handle',
    jwt: c.buyerJwt,
  );
  final prodB1 = await c.rest(
    'GET',
    'products?id=eq.$prod&select=id,seller_id,list_on_marketplace,is_sold,quantity,title',
    jwt: c.buyerJwt,
  );
  final prodSvc = await c.rest(
    'GET',
    'products?id=eq.$prod&select=id,seller_id,list_on_marketplace,is_sold,quantity,title',
    service: true,
  );
  final followUid = await c.rest('POST', 'follows', jwt: c.buyerJwt, body: {
    'follower_id': uid,
    'following_id': s1,
  });
  final favUid = await c.rest('POST', 'favorites', jwt: c.buyerJwt, body: {
    'user_id': uid,
    'product_id': prod,
  });

  final out = {
    'env_b1': b1env,
    'jwt_uid': uid,
    'uid_match': uid == b1env,
    'profile_b1': prof.brief,
    'product_b1': prodB1.brief,
    'product_svc': prodSvc.brief,
    'follow_with_jwt_uid': followUid.brief,
    'fav_with_jwt_uid': favUid.brief,
  };
  await dumpJson('${outDir()}/confirm_a1.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
