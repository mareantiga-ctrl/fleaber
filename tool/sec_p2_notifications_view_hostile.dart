// ignore_for_file: avoid_print
/// P2 G-P2-01 notifications_view scope.
/// dart run tool/sec_p2_notifications_view_hostile.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h,
) async {
  final r = method == 'GET'
      ? await http.get(Uri.parse(u), headers: h)
      : await http.post(Uri.parse(u), headers: h);
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
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
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
    '$url/rest/v1/notifications_view?select=*&limit=5',
    {'apikey': anon, 'Authorization': 'Bearer $anon'},
  );
  final anonRows = anonGet['body'] is List ? anonGet['body'] as List : [];
  add(
    'anon_cannot_read_notifications_view',
    (anonGet['http'] as int) >= 400 || anonRows.isEmpty,
    {'http': anonGet['http'], 'n': anonRows.length, 'body': '${anonGet['text']}'.substring(0, ('${anonGet['text']}'.length).clamp(0, 180))},
  );

  final sellerGet = await req(
    'GET',
    '$url/rest/v1/notifications_view?select=target_user_id,sender_id,product_title&limit=20',
    {
      'apikey': anon,
      'Authorization': 'Bearer $sellerTok',
    },
  );
  final sRows = sellerGet['body'] is List ? sellerGet['body'] as List : [];
  final sellerOnly = sRows.every((r) {
    if (r is! Map) return false;
    return '${r['target_user_id']}' == sellerId;
  });
  add(
    'seller_sees_only_own_targets',
    (sellerGet['http'] as int) < 300 && sellerOnly,
    {'http': sellerGet['http'], 'n': sRows.length},
  );

  final buyerGet = await req(
    'GET',
    '$url/rest/v1/notifications_view?select=target_user_id&limit=20',
    {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
    },
  );
  final bRows = buyerGet['body'] is List ? buyerGet['body'] as List : [];
  final buyerLeak = bRows.any((r) {
    if (r is! Map) return false;
    return '${r['target_user_id']}' != buyerId && '${r['target_user_id']}' == sellerId;
  });
  // Buyer is not a seller of those products → should see 0 (or only if they sell)
  final buyerOk = bRows.every((r) {
    if (r is! Map) return false;
    return '${r['target_user_id']}' == buyerId;
  });
  add(
    'buyer_does_not_see_seller_feed',
    (buyerGet['http'] as int) < 300 && buyerOk && !buyerLeak,
    {'http': buyerGet['http'], 'n': bRows.length},
  );

  final failed = results.where((r) => r['ok'] != true).length;
  final path =
      'tool/reports/sec_p2_notifications_hostile_${DateTime.now().millisecondsSinceEpoch}.json';
  await Directory('tool/reports').create(recursive: true);
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert({
    'tag': 'p2_notifications_view',
    'pass': results.length - failed,
    'fail': failed,
    'results': results,
  }));
  stdout.writeln('\n$failed FAIL / ${results.length} → $path');
  exit(failed == 0 ? 0 : 1);
}
