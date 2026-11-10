import 'dart:io';
import 'live_ops_staging_client.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'));
  final BH = await sb.signIn(email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'), password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'));
  Future<void> g(String label, String path, String tok) async {
    final r = await http.get(Uri.parse('$url$path'), headers: {
      'apikey': anon,
      'Authorization': 'Bearer $tok',
    });
    final b = r.body.length > 240 ? '${r.body.substring(0, 240)}…' : r.body;
    stdout.writeln('$label http=${r.statusCode} $b');
  }
  await g('anon_hub', '/rest/v1/hub_profiles_public?select=*&limit=2', anon);
  await g('buyer_hub', '/rest/v1/hub_profiles_public?select=*&limit=2', BH);
  await g('buyer_dir', '/rest/v1/profiles_directory_public?select=*&limit=2', BH);
  await g('anon_dir', '/rest/v1/profiles_directory_public?select=*&limit=2', anon);
  await g('buyer_own_pii', '/rest/v1/profiles?select=iban,mb_way,phone,shipping_line1,legal_full_name', BH);
}
