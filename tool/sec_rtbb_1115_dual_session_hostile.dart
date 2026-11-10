// ignore_for_file: avoid_print
/// RTBB-1115 dual Session: reuse on create + orphan PI refund path (e2e).
/// dart run tool/sec_rtbb_1115_dual_session_hostile.dart
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
      ? await http.post(
          Uri.parse(u),
          headers: h,
          body: body == null ? null : jsonEncode(body),
        )
      : method == 'GET'
          ? await http.get(Uri.parse(u), headers: h)
          : await http.delete(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body};
}

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    final s = '${(body.first as Map)['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  return null;
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
  final e2eSecret = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
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
  final E2E = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    if (e2eSecret.length >= 16) 'x-fleaber-e2e-secret': e2eSecret,
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final cleanup = <Future Function()>[];

  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'RTBB1115 dual $stamp',
    'price': 8.0,
    'quantity': 2,
    'ref_code': 'RTBB1115-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = idOf(prod['body']);
  add('fixture_product', pid != null, {'id': pid});
  if (pid == null) exit(1);
  cleanup.add(() async {
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
  });

  final o1 = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 8.0,
    'shipping_method': 'hand',
    'payment_method': 'Pagamento na app',
  });
  final oid = idOf(o1['body']);
  add('fixture_order', oid != null, {'id': oid});
  if (oid == null) exit(1);

  final cpi1 = await req(
    'POST',
    '$url/functions/v1/create-payment-intent',
    BH,
    {'buyer_id': buyerId, 'order_id': oid, 'shipping_method': 'hand'},
  );
  final b1 = cpi1['body'] is Map
      ? Map<String, dynamic>.from(cpi1['body'] as Map)
      : <String, dynamic>{};
  final sid1 = '${b1['checkoutSessionId'] ?? ''}';
  add(
    'CPI1_ok',
    (cpi1['http'] as int) == 200 && sid1.startsWith('cs_'),
    {'http': cpi1['http'], 'session': sid1, 'amt': b1['server_amount_cents']},
  );

  final cpi2 = await req(
    'POST',
    '$url/functions/v1/create-payment-intent',
    BH,
    {'buyer_id': buyerId, 'order_id': oid, 'shipping_method': 'hand'},
  );
  final b2 = cpi2['body'] is Map
      ? Map<String, dynamic>.from(cpi2['body'] as Map)
      : <String, dynamic>{};
  final sid2 = '${b2['checkoutSessionId'] ?? ''}';
  final reused = b2['reused_session'] == true || sid2 == sid1;
  add('CPI2_reuses_session', (cpi2['http'] as int) == 200 && reused, {
    'http': cpi2['http'],
    'session': sid2,
    'reused_session': b2['reused_session'],
    'same_as_first': sid2 == sid1,
  });

  // Burst 5: no máximo 1 session id distinto
  final sids = <String>{sid1, sid2};
  for (var i = 0; i < 3; i++) {
    final c = await req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      BH,
      {'buyer_id': buyerId, 'order_id': oid, 'shipping_method': 'hand'},
    );
    final b = c['body'] is Map
        ? Map<String, dynamic>.from(c['body'] as Map)
        : <String, dynamic>{};
    final s = '${b['checkoutSessionId'] ?? ''}';
    if (s.isNotEmpty) sids.add(s);
  }
  add('CPI_burst_unique_sessions_le_1', sids.length <= 1, {
    'unique': sids.length,
    'ids': sids.toList(),
  });

  // Orphan PI path via e2e probe
  final orphan = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'probe': 'orphan_second_pi_refund',
    },
  );
  Map<String, dynamic> ob = {};
  if (orphan['body'] is Map) {
    ob = Map<String, dynamic>.from(orphan['body'] as Map);
  }
  add(
    'P1_orphan_second_pi_refunded',
    orphan['http'] == 200 && ob['ok'] == true,
    {
      'http': orphan['http'],
      'ok': ob['ok'],
      'refund_b': ob['refund_b_id'],
      'order_status': ob['order_status'],
      'clip': '${ob['error'] ?? ob['settle2_clip'] ?? ob}'.length > 220
          ? '${ob['error'] ?? ob['settle2_clip'] ?? ob}'.substring(0, 220)
          : '${ob['error'] ?? ob['settle2_clip'] ?? ob}',
    },
  );

  for (final f in cleanup.reversed) {
    try {
      await f();
    } catch (_) {}
  }

  final pass = results.where((r) => r['ok'] == true).length;
  final fail = results.where((r) => r['ok'] != true).length;
  final outPath = 'tool/reports/sec_rtbb_1115_dual_session_hostile_$stamp.json';
  await File(outPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'stamp': stamp,
      'pass': pass,
      'fail': fail,
      'results': results,
    }),
  );
  stdout.writeln('\n$pass/${results.length} PASS → $outPath');
  exit(fail == 0 ? 0 : 1);
}
