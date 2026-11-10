// ignore_for_file: avoid_print
/// P2 device token + raffle tick authority.
/// dart run tool/sec_p2_device_token_tick_hostile.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> rpc(
  String url,
  String name,
  Map<String, String> h,
  Map<String, dynamic> body,
) async {
  final r = await http.post(
    Uri.parse('$url/rest/v1/rpc/$name'),
    headers: h,
    body: jsonEncode(body),
  );
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
  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
    'Content-Type': 'application/json',
  };
  final SH = {
    'apikey': anon,
    'Authorization': 'Bearer $sellerTok',
    'Content-Type': 'application/json',
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final buyerTokRpc = await rpc(url, 'batata_create_seller_device_token', BH, {
    'p_device_id': 'hostile-buyer-device-p2',
    'p_label': 'p2',
  });
  final bBody = buyerTokRpc['body'];
  final buyerDenied = bBody is Map &&
      (bBody['ok'] == false || bBody['error'] == 'not_seller');
  add(
    'buyer_device_token_denied',
    buyerDenied || (buyerTokRpc['http'] as int) >= 400,
    {'http': buyerTokRpc['http'], 'body': buyerTokRpc['body']},
  );

  final sellerTokRpc = await rpc(url, 'batata_create_seller_device_token', SH, {
    'p_device_id': 'hostile-seller-device-p2',
    'p_label': 'p2',
  });
  final sBody = sellerTokRpc['body'];
  final sellerOk = sBody is Map && sBody['ok'] == true && '${sBody['token'] ?? ''}'.length > 10;
  add(
    'seller_device_token_ok',
    sellerOk,
    {'http': sellerTokRpc['http'], 'ok': sBody is Map ? sBody['ok'] : null},
  );

  // Tick: find any raffle id
  final raffles = await sb.select('live_raffles', limit: 1);
  final rid = raffles.isNotEmpty ? '${raffles.first['id']}' : '';
  if (rid.isEmpty) {
    add('tick_fixture_skip', true, {'note': 'no raffle'});
  } else {
    final buyerTick = await rpc(url, 'batata_tick_live_raffle', BH, {
      'p_raffle_id': rid,
    });
    final bt = buyerTick['body'];
    final buyerTickDenied = bt is Map &&
        (bt['ok'] == false || bt['error'] == 'not_allowed');
    add(
      'buyer_tick_denied',
      buyerTickDenied || (buyerTick['http'] as int) >= 400,
      {'http': buyerTick['http'], 'body': bt},
    );

    // Seller of lab may or may not own this raffle — if owns, ok:true; else not_allowed
    final sellerTick = await rpc(url, 'batata_tick_live_raffle', SH, {
      'p_raffle_id': rid,
    });
    final st = sellerTick['body'];
    final sellerTickOk = st is Map &&
        (st['ok'] == true || st['error'] == 'not_allowed' || st['error'] == 'raffle_not_found');
    add(
      'seller_tick_authorized_or_not_owner',
      (sellerTick['http'] as int) < 300 && sellerTickOk,
      {'http': sellerTick['http'], 'body': st, 'seller_id': sellerId},
    );
  }

  final failed = results.where((r) => r['ok'] != true).length;
  final path =
      'tool/reports/sec_p2_device_tick_hostile_${DateTime.now().millisecondsSinceEpoch}.json';
  await Directory('tool/reports').create(recursive: true);
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert({
    'tag': 'p2_device_tick',
    'pass': results.length - failed,
    'fail': failed,
    'results': results,
  }));
  stdout.writeln('\n$failed FAIL / ${results.length} → $path');
  exit(failed == 0 ? 0 : 1);
}
