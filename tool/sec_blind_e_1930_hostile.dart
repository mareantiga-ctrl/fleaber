// ignore_for_file: avoid_print
/// Blind E 1930 — dart run tool/sec_blind_e_1930_hostile.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> reqNoRedirect(
  String method,
  String u,
  Map<String, String> h,
) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse(u);
    final rq = await client.openUrl(method, uri);
    h.forEach(rq.headers.set);
    rq.followRedirects = false;
    final rs = await rq.close();
    final body = await rs.transform(utf8.decoder).join();
    dynamic p;
    try {
      p = body.isEmpty ? null : jsonDecode(body);
    } catch (_) {
      p = body;
    }
    return {
      'http': rs.statusCode,
      'body': p,
      'text': body,
      'location': rs.headers.value('location'),
    };
  } finally {
    client.close();
  }
}

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
  return {
    'http': r.statusCode,
    'body': p,
    'text': r.body,
    'location': r.headers['location'],
  };
}

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    final m = body.first as Map;
    final s = '${m['id'] ?? m['order_id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  if (body is Map) {
    final s = '${body['id'] ?? body['order_id'] ?? ''}'.trim();
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
  final crashSecret = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
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
  final E2E = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    if (crashSecret.length >= 16) 'x-fleaber-e2e-secret': crashSecret,
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;

  // ---- P1: unlist + ended live + aguarda_pagamento ----
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'E1930 unlist $stamp',
    'price': 8.5,
    'quantity': 1,
    'ref_code': 'E1930U-$stamp',
    'list_on_marketplace': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final prodId = idOf(prod['body']);
  final ended = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'title': 'E1930 ended $stamp',
    'status': 'ended',
    'is_active': false,
  });
  final endedId = idOf(ended['body']);
  final hold = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': prodId,
    'live_id': endedId,
    'status': 'aguarda_pagamento',
    'quantity': 1,
    'price_total': 8.5,
    'shipping_method': 'hand',
    'payment_method': 'Pagamento na app',
  });
  add(
    'P1_unlist_ended_aguarda_blocked',
    (hold['http'] as int) >= 400,
    {'http': hold['http'], 'body': hold['body']},
  );

  // ---- P2: buyer bundle total 0.50 → catalog ----
  final pA = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'E1930 bun A $stamp',
    'price': 20.0,
    'quantity': 2,
    'ref_code': 'E1930A-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pB = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'E1930 bun B $stamp',
    'price': 10.0,
    'quantity': 2,
    'ref_code': 'E1930B-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final idA = idOf(pA['body']);
  final idB = idOf(pB['body']);
  final bun = await req('POST', '$url/rest/v1/product_bundles', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_ids': [idA, idB],
    'subtotal_eur': 0.5,
    'discount_pct': 0,
    'discount_eur': 0,
    'total_eur': 0.5,
    'status': 'pending',
  });
  final bunRow = firstMap(bun['body']);
  final bunId = idOf(bun['body']);
  final total = (bunRow?['total_eur'] as num?)?.toDouble();
  add(
    'P2_bundle_total_from_catalog',
    (bun['http'] as int) < 300 && total != null && total >= 29.9,
    {'http': bun['http'], 'total': total, 'sub': bunRow?['subtotal_eur']},
  );

  if (bunId != null) {
    final acc = await req(
      'PATCH',
      '$url/rest/v1/product_bundles?id=eq.$bunId',
      SH,
      {'status': 'accepted', 'total_eur': 0.5, 'discount_pct': 0},
    );
    final accRow = firstMap(acc['body']);
    final accTotal = (accRow?['total_eur'] as num?)?.toDouble();
    add(
      'P2_seller_accept_keeps_catalog',
      (acc['http'] as int) < 300 &&
          '${accRow?['status']}' == 'accepted' &&
          accTotal != null &&
          accTotal >= 29.9,
      {'http': acc['http'], 'total': accTotal, 'status': accRow?['status']},
    );
  } else {
    add('P2_seller_accept_keeps_catalog', false, bun);
  }

  // ---- P3: attacker.fleaber.pt rejected (não redireciona para lá) ----
  final conn = await reqNoRedirect(
    'GET',
    '$url/functions/v1/create-connect-account?web_return_origin=${Uri.encodeComponent('https://attacker.fleaber.pt/')}',
    {
      'apikey': anon,
      'Authorization': 'Bearer $sellerTok',
    },
  );
  final loc = '${conn['location'] ?? ''}';
  final bodyTxt = '${conn['text'] ?? conn['body'] ?? ''}';
  add(
    'P3_connect_attacker_subdomain_blocked',
    (conn['http'] as int) != 303 &&
        !loc.contains('attacker.fleaber.pt') &&
        !bodyTxt.contains('attacker.fleaber.pt'),
    {'http': conn['http'], 'location': loc},
  );

  // Legitimate fleaber.pt GET → 303 /wallet (não attacker)
  final connOk = await reqNoRedirect(
    'GET',
    '$url/functions/v1/create-connect-account?web_return_origin=${Uri.encodeComponent('https://fleaber.pt/')}',
    {
      'apikey': anon,
      'Authorization': 'Bearer $sellerTok',
    },
  );
  final okLoc = '${connOk['location'] ?? ''}';
  add(
    'anti_reg_connect_fleaber_origin',
    (connOk['http'] as int) == 303 &&
        okLoc.startsWith('https://fleaber.pt/') &&
        !okLoc.contains('attacker'),
    {'http': connOk['http'], 'location': okLoc},
  );

  // Hub sold hidden
  final sold = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'E1930 sold $stamp',
    'price': 3.0,
    'quantity': 0,
    'ref_code': 'E1930S-$stamp',
    'list_on_marketplace': true,
    'is_sold': true,
    'image_urls': <String>[],
  });
  final soldId = idOf(sold['body']);
  final hub = await req(
    'GET',
    '$url/rest/v1/hub_products_public?id=eq.$soldId&select=id',
    AH,
  );
  final hubList = hub['body'] is List ? hub['body'] as List : const [];
  add('P3_hub_hides_sold', hubList.isEmpty, hub['body']);

  // Anti-reg hand concluido
  final paid = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'probe': 'setup_paid_order',
      'initial_qty': 2,
      'shipping_method': 'mao',
    },
  );
  final paidId = idOf(paid['body']);
  if (paidId != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paidId', SVC, {
      'shipping_method': 'mao',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paidId', BH, {
      'status': 'concluido',
    });
    final hs = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$paidId&select=status',
      SVC,
    ))['body']);
    add('anti_reg_hand_concluido_ok', '${hs?['status']}' == 'concluido', hs);
  } else {
    add('anti_reg_hand_concluido_ok', false, paid);
  }

  final fail = results.where((r) => r['ok'] != true).length;
  stdout.writeln('\n=== ${results.length - fail}/${results.length} PASS ===');
  exit(fail == 0 ? 0 : 1);
}
