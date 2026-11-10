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
  final r = await http.post(
    Uri.parse('$url/functions/v1/create-payment-intent'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $tok',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'order_id': '67c0e047-3824-41f3-8594-4e804b67c6de',
      'buyer_id': envRequire(e, 'LIVE_OPS_TEST_BUYER_ID'),
      'shipping_method': 'hand',
    }),
  );
  File('tool/redteam_blind_g_20260829/cpi_raw_body.txt').writeAsStringSync(r.body);
  stdout.writeln('http=${r.statusCode} len=${r.body.length}');
}
