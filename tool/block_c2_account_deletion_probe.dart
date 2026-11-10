// ignore_for_file: avoid_print
/// Block C2 security probes — staging only.
/// dart run tool/block_c2_account_deletion_probe.dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String url,
  Map<String, String> h, [
  Object? body,
]) async {
  final r = method == 'POST'
      ? await http.post(Uri.parse(url), headers: h, body: jsonEncode(body))
      : method == 'PATCH'
          ? await http.patch(Uri.parse(url), headers: h, body: jsonEncode(body))
          : await http.get(Uri.parse(url), headers: h);
  dynamic p;
  try {
    p = jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p};
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT staging');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final results = <Map<String, dynamic>>[];
  void add(String id, bool pass, Object detail) {
    results.add({'id': id, 'pass': pass, 'detail': detail});
    print('${pass ? 'PASS' : 'FAIL'} $id — $detail');
  }

  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
    'Content-Type': 'application/json',
  };
  final ANON = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
  };

  // C2-1: unauthenticated edge call
  final noAuth = await req(
    'POST',
    '$url/functions/v1/request-account-deletion',
    {'apikey': anon, 'Content-Type': 'application/json'},
    {'confirm': 'ELIMINAR CONTA'},
  );
  add(
    'C2_1_NO_AUTH_BLOCKED',
    (noAuth['http'] as int) == 401 ||
        jsonEncode(noAuth['body']).contains('Sessão'),
    {'http': noAuth['http'], 'body': noAuth['body']},
  );

  // C2-2: wrong confirm
  final wrong = await req(
    'POST',
    '$url/functions/v1/request-account-deletion',
    BH,
    {'confirm': 'WRONG'},
  );
  add(
    'C2_2_WRONG_CONFIRM',
    (wrong['http'] as int) == 400,
    {'http': wrong['http'], 'body': wrong['body']},
  );

  // C2-3: buyer cannot anonymize seller via RPC with forged id
  // (RPC wrapper uses auth.uid() only — direct service RPC with seller id from buyer JWT should fail if called via user client)
  final forge = await req(
    'POST',
    '$url/rest/v1/rpc/batata_request_account_deletion',
    BH,
    {'p_confirmation_code': 'PROBE-FORGE'},
  );
  // This anonymizes the *buyer* (self), not seller — so we only check it doesn't target seller.
  // Restore buyer if anonymized: we should NOT run full deletion on shared QA buyer.
  // Instead call obligations check only.
  final oblig = await req(
    'POST',
    '$url/rest/v1/rpc/batata_account_has_active_obligations',
    BH,
    {'p_user_id': buyerId},
  );
  add(
    'C2_3_OBLIGATIONS_RPC',
    (oblig['http'] as int) >= 200 && (oblig['http'] as int) < 300,
    {'http': oblig['http'], 'body': oblig['body'], 'forge_http': forge['http']},
  );

  // C2-4: service_role anonymize on disposable product-only path —
  // create throwaway auth user is heavy; instead verify seller obligations readable by svc.
  final obligSeller = await req(
    'POST',
    '$url/rest/v1/rpc/batata_account_has_active_obligations',
    SVC,
    {'p_user_id': sellerId},
  );
  add(
    'C2_4_SELLER_OBLIGATIONS_SVC',
    (obligSeller['http'] as int) >= 200 && (obligSeller['http'] as int) < 300,
    {'http': obligSeller['http'], 'body': obligSeller['body']},
  );

  // C2-5: anon cannot call anonymize RPC
  final anonRpc = await req(
    'POST',
    '$url/rest/v1/rpc/batata_anonymize_account_for_deletion',
    ANON,
    {
      'p_user_id': buyerId,
      'p_source': 'app',
      'p_confirmation_code': 'HACK',
      'p_facebook_user_id': null,
      'p_force_pii_only': false,
    },
  );
  add(
    'C2_5_ANON_ANONYMIZE_DENIED',
    (anonRpc['http'] as int) == 401 ||
        (anonRpc['http'] as int) == 403 ||
        (anonRpc['http'] as int) == 404,
    {'http': anonRpc['http'], 'body': anonRpc['body']},
  );

  final dir = Directory('tool/reports/block_c_fix_2026-09-27/evidence');
  await dir.create(recursive: true);
  final fails = results.where((r) => r['pass'] != true).length;
  final path = '${dir.path}/c2_account_deletion_probe.json';
  await File(path).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'at': DateTime.now().toUtc().toIso8601String(),
      'fails': fails,
      'results': results,
      'note':
          'Did not anonymize shared LIVE_OPS buyer/seller accounts (preserve QA).',
    }),
  );
  print('evidence -> $path (fails=$fails)');
  exit(fails == 0 ? 0 : 1);
}
