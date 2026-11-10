// ignore_for_file: avoid_print
/// T0850/U0855 — dart run tool/sec_t0850_u0855_hostile.dart
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
      ? await http.post(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body))
      : method == 'PATCH'
          ? await http.patch(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body))
          : await http.get(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p};
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

String? orderIdFromE2E(dynamic body) {
  if (body is Map) {
    final m = Map<String, dynamic>.from(body);
    final direct = '${m['order_id'] ?? ''}'.trim();
    if (direct.isNotEmpty && direct != 'null') return direct;
  }
  return idOf(body);
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
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
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

  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, [Object? d]) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    print('${ok ? 'PASS' : 'FAIL'} $id ${d ?? ''}');
  }

  final paid = await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', E2E, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'probe': 'setup_paid_order',
    'initial_qty': 2,
    'shipping_method': 'mao',
  });
  final oid = orderIdFromE2E(paid['body']);
  add('fixture_paid', oid != null, {'oid': oid});
  if (oid == null) {
    exit(1);
  }

  await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SVC, {
    'shipping_method': 'mao',
    'payment_method': 'pagamento na app',
  });
  await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {'status': 'enviado'});
  await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {'status': 'concluido'});
  await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {'status': 'entregue'});

  final reopen = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {
    'status': 'pago',
  });
  final after = firstMap(
    (await req('GET', '$url/rest/v1/orders?id=eq.$oid&select=status', SVC))['body'],
  );
  add(
    'T_reopen_pago_blocked',
    (reopen['http'] as int) >= 400 && '${after?['status']}' != 'pago',
    {'http': reopen['http'], 'status': after?['status'], 'body': reopen['body']},
  );

  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'offer qty $stamp',
    'price': 25.0,
    'quantity': 4,
    'ref_code': 'OQ$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final pid = idOf(prod['body']);
  String? offerId;
  if (pid != null) {
    final offer = await req('POST', '$url/rest/v1/product_offers', BH, {
      'product_id': pid,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 6,
      'status': 'pending',
      'offered_by': 'buyer',
    });
    offerId = idOf(offer['body']);
    if (offerId != null) {
      await req('PATCH', '$url/rest/v1/product_offers?id=eq.$offerId', SH, {
        'status': 'accepted',
      });
    }
    final qty3 = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'product_offer_id': offerId,
      'quantity': 3,
      'price_total': 6,
      'status': 'reserva_pendente',
      'payment_method': 'pagamento na app',
    });
    add(
      'U_offer_qty3_blocked',
      (qty3['http'] as int) >= 400,
      {'http': qty3['http'], 'body': qty3['body']},
    );
  } else {
    add('U_offer_qty3_blocked', false, 'no product');
  }

  final fails = results.where((r) => r['ok'] != true).length;
  print('--- T0850/U0855 hostile ${results.length - fails}/${results.length} PASS ---');
  exit(fails > 0 ? 1 : 0);
}
