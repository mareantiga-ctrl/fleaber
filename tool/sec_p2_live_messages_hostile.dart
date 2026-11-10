// ignore_for_file: avoid_print
/// P2 LIVE-MSG: facebook channel scoped to seller.
/// dart run tool/sec_p2_live_messages_hostile.dart
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
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
  };
  final SH = {
    'apikey': anon,
    'Authorization': 'Bearer $sellerTok',
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;
  // Fixture live ended + facebook message (service)
  final liveIns = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'title': 'P2 live msg $stamp',
    'status': 'ended',
    'is_active': false,
  });
  String? liveId;
  if (liveIns['body'] is List && (liveIns['body'] as List).isNotEmpty) {
    liveId = '${(liveIns['body'] as List).first['id']}';
  } else if (liveIns['body'] is Map) {
    liveId = '${(liveIns['body'] as Map)['id']}';
  }
  add('fixture_live', liveId != null, {'live_id': liveId, 'http': liveIns['http']});
  if (liveId == null) {
    exit(1);
  }

  final msgFb = await req('POST', '$url/rest/v1/live_messages', SVC, {
    'live_id': liveId,
    'kind': 'chat',
    'body': 'OCR Bruno Teixeira P2',
    'sender_label': 'Bruno Teixeira',
    'channel': 'facebook',
  });
  final msgApp = await req('POST', '$url/rest/v1/live_messages', SVC, {
    'live_id': liveId,
    'kind': 'chat',
    'body': 'ola fleaber',
    'sender_label': 'Buyer',
    'channel': 'fleaber',
    'user_id': buyerId,
  });
  add('fixture_messages', msgFb['http'] == 201 && msgApp['http'] == 201, {
    'fb': msgFb['http'],
    'app': msgApp['http'],
  });

  final buyerFb = await req(
    'GET',
    '$url/rest/v1/live_messages?live_id=eq.$liveId&channel=eq.facebook&select=id,body,sender_label,channel',
    BH,
  );
  final bf = buyerFb['body'] is List ? buyerFb['body'] as List : [];
  add(
    'buyer_cannot_read_facebook_channel',
    bf.isEmpty,
    {'http': buyerFb['http'], 'n': bf.length, 'body': buyerFb['text']},
  );

  final buyerApp = await req(
    'GET',
    '$url/rest/v1/live_messages?live_id=eq.$liveId&channel=eq.fleaber&select=id,body,channel',
    BH,
  );
  final ba = buyerApp['body'] is List ? buyerApp['body'] as List : [];
  add(
    'buyer_can_read_fleaber_chat',
    ba.isNotEmpty,
    {'http': buyerApp['http'], 'n': ba.length},
  );

  final sellerFb = await req(
    'GET',
    '$url/rest/v1/live_messages?live_id=eq.$liveId&channel=eq.facebook&select=id,body,sender_label',
    SH,
  );
  final sf = sellerFb['body'] is List ? sellerFb['body'] as List : [];
  add(
    'seller_can_read_facebook_channel',
    sf.isNotEmpty,
    {'http': sellerFb['http'], 'n': sf.length},
  );

  // Cleanup
  await req('DELETE', '$url/rest/v1/live_messages?live_id=eq.$liveId', SVC);
  await req('DELETE', '$url/rest/v1/lives?id=eq.$liveId', SVC);

  final failed = results.where((r) => r['ok'] != true).length;
  final path =
      'tool/reports/sec_p2_live_messages_hostile_${DateTime.now().millisecondsSinceEpoch}.json';
  await Directory('tool/reports').create(recursive: true);
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert({
    'tag': 'p2_live_messages',
    'pass': results.length - failed,
    'fail': failed,
    'results': results,
  }));
  stdout.writeln('\n$failed FAIL / ${results.length} → $path');
  exit(failed == 0 ? 0 : 1);
}
