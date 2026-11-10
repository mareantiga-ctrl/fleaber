// ignore_for_file: avoid_print
/// RTI4-1916 — dart run tool/sec_rti4_1916_hostile.dart
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

bool bodyHas(dynamic body, String needle) {
  return jsonEncode(body ?? '').toLowerCase().contains(needle.toLowerCase());
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
  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
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

  // ---- Fixture: unlist product + ended live (same seller) ----
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'RTI4 unlist ended $stamp',
    'price': 9.5,
    'quantity': 2,
    'ref_code': 'RTI4U-$stamp',
    'list_on_marketplace': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final prodId = idOf(prod['body']);
  add('fixture_unlist', prodId != null, {'id': prodId});

  final endedLive = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'title': 'RTI4 ended $stamp',
    'status': 'ended',
    'is_active': false,
  });
  final endedId = idOf(endedLive['body']);
  add('fixture_ended_live', endedId != null, {'id': endedId, 'http': endedLive['http']});

  // P1: hold with ended live_id must FAIL
  final holdEnded = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': prodId,
    'live_id': endedId,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 9.5,
    'shipping_method': 'mao',
    'payment_method': 'Pagamento na app',
  });
  add(
    'P1_unlist_ended_live_hold_blocked',
    (holdEnded['http'] as int) >= 400 &&
        bodyHas(holdEnded['body'], 'order_hold_product_not_listed'),
    {'http': holdEnded['http'], 'body': holdEnded['body']},
  );

  // P1: fake raffle must FAIL (no ghost hold)
  final holdRaffle = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': prodId,
    'live_raffle_id': '00000000-0000-4000-8000-000000000099',
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 9.5,
    'shipping_method': 'mao',
    'payment_method': 'Pagamento na app',
  });
  add(
    'P1_fake_raffle_hold_blocked',
    (holdRaffle['http'] as int) >= 400,
    {'http': holdRaffle['http'], 'body': holdRaffle['body']},
  );

  // Stock still free after failed raffle probe
  final stock = await req(
    'POST',
    '$url/rest/v1/rpc/batata_product_checkout_available',
    SVC,
    {
      'p_product_id': prodId,
      'p_exclude_order_id': null,
      'p_need_qty': 1,
    },
  );
  final stockMap = firstMap(stock['body']) ??
      (stock['body'] is Map
          ? Map<String, dynamic>.from(stock['body'] as Map)
          : null);
  add(
    'P1_stock_free_after_raffle_fail',
    stockMap?['ok'] == true &&
        (stockMap?['held'] == 0 || stockMap?['held'] == '0'),
    stockMap,
  );

  // Active live + unlist → hold OK (não regressão live)
  final activeLive = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'title': 'RTI4 active $stamp',
    'status': 'live',
    'is_active': true,
  });
  final activeId = idOf(activeLive['body']);
  add('fixture_active_live', activeId != null, {'id': activeId});

  final holdActive = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': prodId,
    'live_id': activeId,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 9.5,
    'shipping_method': 'mao',
    'payment_method': 'Pagamento na app',
  });
  final activeOrderId = idOf(holdActive['body']);
  add(
    'anti_reg_unlist_active_live_hold_ok',
    (holdActive['http'] as int) < 300 && activeOrderId != null,
    {'http': holdActive['http'], 'id': activeOrderId},
  );

  // Edge: if somehow order had ended live (SVC seed) → checkout blocked
  final ghost = await req('POST', '$url/rest/v1/orders', SVC, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': prodId,
    'live_id': endedId,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 9.5,
    'shipping_method': 'mao',
    'payment_method': 'Pagamento na app',
  });
  final ghostId = idOf(ghost['body']);
  // Cancel active hold first so stock allows? ghost uses same product qty 2, active holds 1 — ghost can hold via SVC
  if (ghostId != null) {
    final cpi = await req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      BH,
      {
        'order_id': ghostId,
        'buyer_id': buyerId,
        'shipping_method': 'mao',
      },
    );
    final cpiText = '${cpi['text'] ?? cpi['body']}';
    add(
      'P1_edge_ended_live_checkout_blocked',
      (cpi['http'] as int) >= 400 &&
          cpiText.toLowerCase().contains('not listed'),
      {'http': cpi['http'], 'body': cpi['body']},
    );
    await req('PATCH', '$url/rest/v1/orders?id=eq.$ghostId', SVC, {
      'status': 'cancelado',
    });
  } else {
    add('P1_edge_ended_live_checkout_blocked', false, ghost);
  }

  // P2: sold product not in hub_products_public
  final sold = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'RTI4 sold hub $stamp',
    'price': 4.0,
    'quantity': 0,
    'ref_code': 'RTI4S-$stamp',
    'list_on_marketplace': true,
    'is_sold': true,
    'image_urls': <String>[],
  });
  final soldId = idOf(sold['body']);
  final hub = await req(
    'GET',
    '$url/rest/v1/hub_products_public?id=eq.$soldId&select=id,is_sold',
    AH,
  );
  final hubList = hub['body'] is List ? hub['body'] as List : const [];
  add(
    'P2_hub_hides_sold',
    (hub['http'] as int) < 300 && hubList.isEmpty,
    {'http': hub['http'], 'body': hub['body'], 'soldId': soldId},
  );

  // Anti-reg: listed product hold OK
  final listed = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'RTI4 listed $stamp',
    'price': 5.0,
    'quantity': 2,
    'ref_code': 'RTI4L-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final listedId = idOf(listed['body']);
  final holdListed = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': listedId,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 5.0,
    'shipping_method': 'mao',
    'payment_method': 'Pagamento na app',
  });
  final listedOrderId = idOf(holdListed['body']);
  add(
    'anti_reg_listed_hold_ok',
    (holdListed['http'] as int) < 300 && listedOrderId != null,
    {'http': holdListed['http'], 'id': listedOrderId},
  );

  // Anti-reg: mão pago → concluido
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
    await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$paidId',
      SVC,
      {'shipping_method': 'mao'},
    );
    final concl = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$paidId',
      BH,
      {'status': 'concluido'},
    );
    final hs = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$paidId&select=status,shipping_method',
      SVC,
    ))['body']);
    add(
      'anti_reg_hand_concluido_ok',
      '${hs?['status']}' == 'concluido',
      {'http': concl['http'], 'status': hs?['status'], 'ship': hs?['shipping_method']},
    );
  } else {
    add('anti_reg_hand_concluido_ok', false, paid);
  }

  // Cleanup: end active live + cancel holds
  if (activeId != null) {
    await req('PATCH', '$url/rest/v1/lives?id=eq.$activeId', SVC, {
      'status': 'ended',
      'is_active': false,
    });
  }
  for (final oid in [activeOrderId, listedOrderId]) {
    if (oid != null) {
      await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SVC, {
        'status': 'cancelado',
      });
    }
  }

  final fail = results.where((r) => r['ok'] != true).length;
  stdout.writeln('\n=== ${results.length - fail}/${results.length} PASS ===');
  exit(fail == 0 ? 0 : 1);
}
