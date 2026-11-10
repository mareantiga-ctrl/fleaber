// ignore_for_file: avoid_print
/// dart run tool/sec_dtdy_20260906_hostile.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
]) async {
  final client = http.Client();
  try {
    late http.Response r;
    final uri = Uri.parse(u);
    if (method == 'POST') {
      r = await client.post(uri,
          headers: h, body: body == null ? null : jsonEncode(body));
    } else if (method == 'GET') {
      r = await client.get(uri, headers: h);
    } else {
      r = await client.patch(uri,
          headers: h, body: body == null ? null : jsonEncode(body));
    }
    dynamic p;
    try {
      p = r.body.isEmpty ? null : jsonDecode(r.body);
    } catch (_) {
      p = r.body;
    }
    return {'http': r.statusCode, 'body': p, 'raw': r.body};
  } finally {
    client.close();
  }
}

void pass(String id) => print('PASS $id');
void fail(String id, String why) {
  print('FAIL $id: $why');
  exitCode = 1;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final buyerId = await sb.userIdForAccessToken(buyerTok);
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final oid = '00000000-0000-0000-0000-000000000099';

  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
  };

  // DV: REST direct insert denied
  final ins = await req(
    'POST',
    '$url/rest/v1/batata_private_object_revoked',
    BH,
    {'object_path': 'order_disputes/other/x-$stamp.png'},
  );
  (ins['http'] == 401 || ins['http'] == 403 || ins['http'] >= 400)
      ? pass('dv-rest-deny')
      : fail('dv-rest-deny', '${ins['http']} ${ins['raw']}');

  // Revoke own path + proof_ok false
  final path = 'order_disputes/$buyerId/$oid/gone-$stamp.png';
  final rev = await req(
    'POST',
    '$url/rest/v1/rpc/batata_revoke_private_object',
    BH,
    {'p_path': path},
  );
  rev['body'] == true ? pass('dv-revoke') : fail('dv-revoke', '${rev['raw']}');

  final clean =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$path';
  final ok = await req(
    'POST',
    '$url/rest/v1/rpc/batata_dispute_proof_url_ok',
    SVC,
    {'p_url': clean, 'p_buyer': buyerId, 'p_oid': oid},
  );
  ok['body'] == false
      ? pass('dv-proof-revoked')
      : fail('dv-proof-revoked', '${ok['raw']}');

  if (exitCode == 0) print('ALL PASS');
}
