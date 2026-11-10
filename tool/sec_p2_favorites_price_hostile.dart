// ignore_for_file: avoid_print
/// P2 favorites + price_total floor.
/// dart run tool/sec_p2_favorites_price_hostile.dart
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
    'Prefer': 'return=representation',
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final anonFav = await req(
    'GET',
    '$url/rest/v1/favorites?select=*&limit=5',
    {'apikey': anon, 'Authorization': 'Bearer $anon'},
  );
  add(
    'anon_favorites_denied',
    (anonFav['http'] as int) >= 400,
    {'http': anonFav['http']},
  );

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'P2 fav $stamp',
    'price': 6.5,
    'quantity': 2,
    'ref_code': 'P2F-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = prod['body'] is List && (prod['body'] as List).isNotEmpty
      ? '${(prod['body'] as List).first['id']}'
      : '';
  add('fixture_product', pid.isNotEmpty, {'id': pid});

  final ord = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 1,
    'price_total': 0.01,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
  });
  Map<String, dynamic>? row;
  if (ord['body'] is List && (ord['body'] as List).isNotEmpty) {
    row = Map<String, dynamic>.from((ord['body'] as List).first as Map);
  }
  final pt = row?['price_total'];
  final cu = row?['contract_unit_cents'];
  final ptNum = pt is num ? pt.toDouble() : double.tryParse('$pt');
  final floorOk =
      ptNum != null && ptNum >= 6.4 && (cu == 650 || cu == 650.0);
  add(
    'price_total_floored_to_contract',
    (ord['http'] as int) < 300 && floorOk,
    {'http': ord['http'], 'price_total': pt, 'contract_unit_cents': cu, 'body': '${ord['text']}'.substring(0, ('${ord['text']}'.length).clamp(0, 200))},
  );

  if (ord['body'] is List && (ord['body'] as List).isNotEmpty) {
    final oid = '${(ord['body'] as List).first['id']}';
    await req('DELETE', '$url/rest/v1/orders?id=eq.$oid', SVC);
  }
  if (pid.isNotEmpty) {
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
  }

  final failed = results.where((r) => r['ok'] != true).length;
  final path =
      'tool/reports/sec_p2_favorites_price_hostile_${DateTime.now().millisecondsSinceEpoch}.json';
  await Directory('tool/reports').create(recursive: true);
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert({
    'tag': 'p2_favorites_price',
    'pass': results.length - failed,
    'fail': failed,
    'results': results,
  }));
  stdout.writeln('\n$failed FAIL / ${results.length} → $path');
  exit(failed == 0 ? 0 : 1);
}
