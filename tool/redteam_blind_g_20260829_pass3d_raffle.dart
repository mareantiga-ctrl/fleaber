import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final tok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final h = {
    'apikey': anon,
    'Authorization': 'Bearer $tok',
    'Content-Type': 'application/json',
  };
  final r = await http.post(
    Uri.parse('$url/rest/v1/rpc/batata_create_raffle_prize_order'),
    headers: h,
    body: jsonEncode({
      'p_raffle_id': envRequire(e, 'LIVE_OPS_TEST_BUYER_ID'),
      'p_rank': 1,
      'p_winner_uid': envRequire(e, 'LIVE_OPS_TEST_BUYER_ID'),
    }),
  );
  stdout.writeln('prize ${r.statusCode} ${r.body}');
  final r2 = await http.get(
    Uri.parse('$url/rest/v1/live_raffle_winners?select=*&limit=1'),
    headers: h,
  );
  stdout.writeln('winners_select ${r2.statusCode} ${r2.body.substring(0, r2.body.length.clamp(0, 300))}');
  final r3 = await http.post(
    Uri.parse('$url/rest/v1/live_raffle_winners'),
    headers: {...h, 'Prefer': 'return=representation'},
    body: r2.body.startsWith('[') && r2.body.length > 2 ? r2.body : '{}',
  );
  stdout.writeln('winners_probe_skip insert_http=${r3.statusCode} ${r3.body.substring(0, r3.body.length.clamp(0, 200))}');
}
