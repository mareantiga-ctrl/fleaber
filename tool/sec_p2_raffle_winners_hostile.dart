// ignore_for_file: avoid_print
/// P2 raffle winners scope (no global draw_proof enum).
/// dart run tool/sec_p2_raffle_winners_hostile.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h,
) async {
  final r = await http.get(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body};
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final buyerAll = await req(
    'GET',
    '$url/rest/v1/live_raffle_winners?select=id,user_id,draw_proof&limit=20',
    {'apikey': anon, 'Authorization': 'Bearer $buyerTok'},
  );
  final bRows = buyerAll['body'] is List ? buyerAll['body'] as List : [];
  // Buyer só vê rows onde user_id=self (se alguma)
  final buyerOk = bRows.every((r) {
    if (r is! Map) return false;
    return '${r['user_id']}' == envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  });
  add(
    'buyer_no_global_winners_enum',
    (buyerAll['http'] as int) < 300 && buyerOk,
    {'http': buyerAll['http'], 'n': bRows.length},
  );

  final sellerAll = await req(
    'GET',
    '$url/rest/v1/live_raffle_winners?select=id,user_id,raffle_id&limit=50',
    {'apikey': anon, 'Authorization': 'Bearer $sellerTok'},
  );
  add(
    'seller_select_ok',
    (sellerAll['http'] as int) < 300,
    {'http': sellerAll['http'], 'n': sellerAll['body'] is List ? (sellerAll['body'] as List).length : -1},
  );

  // RPC state still works (public winners without draw_proof)
  final lives = await sb.select(
    'lives',
    filter: 'or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)',
    limit: 3,
  );
  var rpcOk = true;
  Object? rpcDetail;
  for (final live in lives) {
    final lid = '${live['id']}';
    final r = await http.post(
      Uri.parse('$url/rest/v1/rpc/batata_get_live_raffle_state'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerTok',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'p_live_id': lid}),
    );
    if (r.statusCode >= 400) {
      rpcOk = false;
      rpcDetail = r.body;
      break;
    }
    rpcDetail = {'live_id': lid, 'http': r.statusCode};
  }
  add('rpc_get_live_raffle_state_ok', rpcOk || lives.isEmpty, rpcDetail);

  final failed = results.where((r) => r['ok'] != true).length;
  final path =
      'tool/reports/sec_p2_raffle_winners_hostile_${DateTime.now().millisecondsSinceEpoch}.json';
  await Directory('tool/reports').create(recursive: true);
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert({
    'tag': 'p2_raffle_winners',
    'pass': results.length - failed,
    'fail': failed,
    'results': results,
  }));
  stdout.writeln('\n$failed FAIL / ${results.length} → $path');
  exit(failed == 0 ? 0 : 1);
}
