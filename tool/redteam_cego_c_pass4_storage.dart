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
  final buyerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final buyerId = await sb.userIdForAccessToken(buyerJwt);
  const sellerId = '980f4fa1-0004-42f9-abca-69f1a9c29588';
  Map<String, String> h(String jwt) => {
        'apikey': anon,
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
      };

  Future<String> list(String prefix) async {
    final r = await http.post(
      Uri.parse('$base/storage/v1/object/list/fleaber_private'),
      headers: h(buyerJwt),
      body: jsonEncode({'prefix': prefix, 'limit': 8}),
    );
    final b = r.body.length > 400 ? r.body.substring(0, 400) : r.body;
    return '${r.statusCode} $b';
  }

  final out = {
    'chat_uploads_root': await list('chat_uploads'),
    'chat_uploads_seller': await list('chat_uploads/$sellerId'),
    'chat_uploads_buyer': await list('chat_uploads/$buyerId'),
    'order_proofs': await list('order_proofs'),
    'order_disputes': await list('order_disputes'),
    'order_proofs_seller': await list('order_proofs/$sellerId'),
  };

  // try download a guessed path
  final dl = await http.get(
    Uri.parse(
      '$base/storage/v1/object/fleaber_private/chat_uploads/$sellerId/cego.txt',
    ),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
    },
  );
  out['download_seller_file'] = '${dl.statusCode} ${dl.body.length > 120 ? dl.body.substring(0, 120) : dl.body}';

  File('tool/reports/redteam_cego_c_20260829/pass4_storage.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
