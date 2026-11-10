// ignore_for_file: avoid_print
/// P2 follows ego-scope.
/// dart run tool/sec_p2_follows_hostile.dart
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
  final r = method == 'POST'
      ? await http.post(Uri.parse(u), headers: h, body: jsonEncode(body))
      : method == 'DELETE'
          ? await http.delete(Uri.parse(u), headers: h)
          : await http.get(Uri.parse(u), headers: h);
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
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
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

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final anonGet = await req(
    'GET',
    '$url/rest/v1/follows?select=*&limit=5',
    {'apikey': anon, 'Authorization': 'Bearer $anon'},
  );
  add(
    'anon_follows_denied',
    (anonGet['http'] as int) >= 400 ||
        (anonGet['body'] is List && (anonGet['body'] as List).isEmpty),
    {'http': anonGet['http']},
  );

  final buyerGet = await req(
    'GET',
    '$url/rest/v1/follows?select=follower_id,following_id&limit=50',
    {'apikey': anon, 'Authorization': 'Bearer $buyerTok'},
  );
  final rows = buyerGet['body'] is List ? buyerGet['body'] as List : [];
  final scoped = rows.every((r) {
    if (r is! Map) return false;
    return '${r['follower_id']}' == buyerId || '${r['following_id']}' == buyerId;
  });
  add(
    'buyer_only_ego_follows',
    (buyerGet['http'] as int) < 300 && scoped,
    {'http': buyerGet['http'], 'n': rows.length},
  );

  // Happy: follow seller then unfollow
  await req(
    'DELETE',
    '$url/rest/v1/follows?follower_id=eq.$buyerId&following_id=eq.$sellerId',
    {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
    },
  );
  final ins = await req(
    'POST',
    '$url/rest/v1/follows',
    {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    },
    {'follower_id': buyerId, 'following_id': sellerId},
  );
  add(
    'buyer_can_follow',
    (ins['http'] as int) < 300,
    {'http': ins['http'], 'body': '${ins['text']}'.substring(0, ('${ins['text']}'.length).clamp(0, 120))},
  );
  final del = await req(
    'DELETE',
    '$url/rest/v1/follows?follower_id=eq.$buyerId&following_id=eq.$sellerId',
    {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
    },
  );
  add('buyer_can_unfollow', (del['http'] as int) < 300, {'http': del['http']});

  final spoof = await req(
    'POST',
    '$url/rest/v1/follows',
    {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    },
    {'follower_id': sellerId, 'following_id': buyerId},
  );
  add(
    'buyer_cannot_forge_other_follower',
    (spoof['http'] as int) >= 400,
    {'http': spoof['http']},
  );

  final failed = results.where((r) => r['ok'] != true).length;
  final path =
      'tool/reports/sec_p2_follows_hostile_${DateTime.now().millisecondsSinceEpoch}.json';
  await Directory('tool/reports').create(recursive: true);
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert({
    'tag': 'p2_follows',
    'pass': results.length - failed,
    'fail': failed,
    'results': results,
  }));
  stdout.writeln('\n$failed FAIL / ${results.length} → $path');
  exit(failed == 0 ? 0 : 1);
}
