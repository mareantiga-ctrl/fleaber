import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

void main() async {
  Directory.current = File(Platform.script.toFilePath()).parent.parent.path;
  final env = loadLiveOpsStagingEnv();
  final base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final sb = LiveOpsStagingClient(
    url: base,
    anonKey: anon,
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final sellerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  Map<String, String> h(String jwt) => {
        'apikey': anon,
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
      };

  Future<String> rpc(String jwt, Map body) async {
    final r = await http.post(
      Uri.parse('$base/rest/v1/rpc/batata_find_user_id_by_email'),
      headers: h(jwt),
      body: jsonEncode(body),
    );
    return '${r.statusCode} ${r.body}';
  }

  final emails = [
    'nobody-cego@invalid.example',
    'test@gmail.com',
    'admin@fleaber.pt',
    envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
  ];
  final out = <String, String>{};
  for (final e in emails) {
    out['seller_$e'] = await rpc(sellerJwt, {'p_email': e});
    out['buyer_$e'] = await rpc(buyerJwt, {'p_email': e});
  }

  // private storage
  final privList = await http.post(
    Uri.parse('$base/storage/v1/object/list/fleaber_private'),
    headers: h(buyerJwt),
    body: jsonEncode({'prefix': '', 'limit': 10}),
  );
  out['private_list_buyer'] = '${privList.statusCode} ${privList.body}';
  final pubList = await http.post(
    Uri.parse('$base/storage/v1/object/list/chat_media'),
    headers: h(buyerJwt),
    body: jsonEncode({'prefix': '', 'limit': 5}),
  );
  out['public_list_buyer'] = '${pubList.statusCode} ${pubList.body}';
  final pubAnon = await http.get(
    Uri.parse('$base/storage/v1/object/public/chat_media/cego_nope.txt'),
    headers: {'apikey': anon},
  );
  out['public_get_missing'] = '${pubAnon.statusCode}';

  // profiles seller as buyer (no email col)
  final prof = await http.get(
    Uri.parse('$base/rest/v1/profiles?select=id,full_name,phone,user_type&id=eq.980f4fa1-0004-42f9-abca-69f1a9c29588'),
    headers: h(buyerJwt),
  );
  out['profile_seller'] = '${prof.statusCode} ${prof.body}';

  File('tool/reports/redteam_cego_c_20260829/pass3.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
