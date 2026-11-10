// ignore_for_file: avoid_print
/// RTG/F/Indep fixes — dart run tool/sec_rtg_f_indep_20260831_hostile.dart
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
      : method == 'PATCH'
          ? await http.patch(
              Uri.parse(u),
              headers: h,
              body: body == null ? null : jsonEncode(body),
            )
          : await http.get(Uri.parse(u), headers: h);
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
  if (body is Map && body['id'] != null) {
    final s = '${body['id']}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  return null;
}

Map<String, dynamic>? firstMap(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
  return null;
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
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SH = {
    'apikey': anon,
    'Authorization': 'Bearer $sellerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final AH = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
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

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final created = <String>[];

  try {
    // P1 cancel hold
    final p = await req('POST', '$url/rest/v1/products', SVC, {
      'seller_id': sellerId,
      'title': 'RTFIX cancel $stamp',
      'price': 9.0,
      'quantity': 2,
      'ref_code': 'RTFC-$stamp',
      'list_on_marketplace': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final pid = idOf(p['body']);
    final hold = await req('POST', '$url/rest/v1/orders', BH, {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'product_id': pid,
      'status': 'reserva_pendente',
      'quantity': 1,
      'price_total': 9.0,
      'shipping_method': 'mao',
      'payment_method': 'Pagamento na app',
    });
    final oid = idOf(hold['body']);
    if (oid != null) created.add(oid);
    final cancel = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$oid',
      SH,
      {'status': 'cancelado'},
    );
    final after = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$oid&select=status,wallet_release_processed_at',
      SVC,
    ))['body']);
    add(
      'P1_cancel_hold',
      cancel['http'] == 200 &&
          '${after?['status']}'.toLowerCase().contains('cancel'),
      {'http': cancel['http'], 'after': after},
    );

    // 5-A offer unlist
    final un = await req('POST', '$url/rest/v1/products', SVC, {
      'seller_id': sellerId,
      'title': 'RTFIX unlist $stamp',
      'price': 3.0,
      'quantity': 1,
      'ref_code': 'RTFU-$stamp',
      'list_on_marketplace': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final unid = idOf(un['body']);
    final off = await req('POST', '$url/rest/v1/product_offers', BH, {
      'product_id': unid,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 2.0,
      'offered_by': 'buyer',
      'status': 'pending',
    });
    add(
      '5A_offer_unlist_blocked',
      (off['http'] as int) >= 400,
      {'http': off['http'], 'body': off['body']},
    );

    // 1-A paused hidden from hub (fixture paused item on published ended live)
    final ended = await req('POST', '$url/rest/v1/lives', SVC, {
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'title': 'RTFIX paused $stamp',
      'status': 'ended',
      'is_active': false,
    });
    final lid = idOf(ended['body']);
    final item = await req('POST', '$url/rest/v1/live_items', SVC, {
      'live_id': lid,
      'title': 'paused-secret-fix',
      'price': 199.5,
      'status': 'paused',
      'is_active': false,
      'ref_code': 'PAUSE-$stamp',
    });
    final iid = idOf(item['body']);
    await req(
      'POST',
      '$url/rest/v1/rpc/batata_publish_hub',
      SH,
      {'p_publish': true},
    );
    final hub = await req(
      'GET',
      '$url/rest/v1/hub_live_items_public?live_id=eq.$lid&select=id,title',
      AH,
    );
    final hubRows = hub['body'] is List ? (hub['body'] as List).length : -1;
    add('1A_paused_hidden_hub', hubRows == 0, {
      'http': hub['http'],
      'rows': hubRows,
      'item': iid,
    });

    // 3-A pairing on ended blocked
    final pair = await req(
      'POST',
      '$url/rest/v1/rpc/batata_ps_create_pairing',
      SH,
      {'p_live_id': lid, 'p_device_id_hint': 'rtfix-$stamp'},
    );
    final pairBody = pair['body'];
    add(
      '3A_pairing_ended_blocked',
      (pair['http'] as int) == 200 &&
          pairBody is Map &&
          pairBody['ok'] != true,
      {'http': pair['http'], 'body': pairBody},
    );
  } finally {
    for (final id in created) {
      await req(
        'PATCH',
        '$url/rest/v1/orders?id=eq.$id',
        SVC,
        {'status': 'cancelado'},
      );
    }
  }

  final failed = results.where((r) => r['ok'] != true).length;
  stdout.writeln('--- ${results.length - failed}/${results.length} PASS ---');
  exit(failed == 0 ? 0 : 1);
}
