// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final e2e = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
  final r = await http.post(
    Uri.parse('$url/functions/v1/sec-fase2-e2e-oversell'),
    headers: {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
      'Content-Type': 'application/json',
      if (e2e.length >= 16) 'x-fleaber-e2e-secret': e2e,
    },
    body: jsonEncode({
      'buyer_id': envRequire(e, 'LIVE_OPS_TEST_BUYER_ID'),
      'seller_id': envRequire(e, 'LIVE_OPS_TEST_SELLER_ID'),
    }),
  );
  print('http=${r.statusCode}');
  print(r.body);
  final ok = r.statusCode == 200 && r.body.contains('"ok": true');
  exit(ok ? 0 : 1);
}
