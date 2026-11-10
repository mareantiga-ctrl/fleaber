// RTC C pass 3 — 2ª reprodução P0 disputa+stripe-refund + ordem inversa.
// dart run tool/rtc_deep_cash_20260830T0900_pass3.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

late String url, anon, svc, buyerJwt, sellerJwt, buyerId, sellerId;
String? e2eSecret;
final createdO = <String>[];
final createdP = <String>[];
final createdD = <String>[];

Future<http.Response> call(String method, String path,
    {String? token, Object? body, bool service = false, Map<String, String>? extra}) {
  final h = <String, String>{
    'apikey': service ? svc : anon,
    'Authorization': 'Bearer ${service ? svc : (token ?? anon)}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
    ...?extra,
  };
  final uri = Uri.parse('$url$path');
  if (method == 'GET') return http.get(uri, headers: h);
  if (method == 'PATCH') return http.patch(uri, headers: h, body: jsonEncode(body));
  if (method == 'DELETE') return http.delete(uri, headers: h);
  return http.post(uri, headers: h, body: body == null ? null : jsonEncode(body));
}

dynamic dec(http.Response r) {
  try {
    return jsonDecode(r.body);
  } catch (_) {
    return r.body;
  }
}

Map<String, dynamic>? first(dynamic d) {
  if (d is List && d.isNotEmpty && d.first is Map) return Map<String, dynamic>.from(d.first as Map);
  if (d is Map) return Map<String, dynamic>.from(d);
  return null;
}

Future<num> bal(String id) async {
  final r = await call('GET', '/rest/v1/wallets?id=eq.$id&select=balance', service: true);
  return (first(dec(r))?['balance'] as num?) ?? 0;
}

Future<Map<String, dynamic>?> order(String id) async {
  final r = await call(
    'GET',
    '/rest/v1/orders?id=eq.$id&select=id,status,amount_paid_cents,stripe_refund_id,wallet_refund_processed_at,wallet_release_processed_at',
    service: true,
  );
  return first(dec(r));
}

Future<http.Response> e2e(Map<String, dynamic> body) => call(
      'POST',
      '/functions/v1/sec-fase2-e2e-oversell',
      token: anon,
      body: body,
      extra: {if (e2eSecret != null) 'x-fleaber-e2e-secret': e2eSecret!},
    );

Future<Map<String, dynamic>> paidOrder() async {
  final setup = await e2e({
    'probe': 'setup_paid_order',
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'initial_qty': 2,
  });
  final p = first(dec(setup))!;
  createdO.add(p['order_id'].toString());
  createdP.add(p['product_id'].toString());
  final oid = p['order_id'].toString();
  await call('PATCH', '/rest/v1/orders?id=eq.$oid', token: sellerJwt, body: {'status': 'enviado'});
  await call('PATCH', '/rest/v1/orders?id=eq.$oid', token: sellerJwt, body: {'status': 'entregue'});
  return p;
}

Future<void> offer100(String oid) async {
  final disp = await call('POST', '/rest/v1/order_disputes', token: buyerJwt, body: {
    'order_id': oid,
    'buyer_id': buyerId,
    'reason': 'outro',
    'description': 'RTC p3',
  });
  final dr = first(dec(disp));
  if (dr?['id'] == null) {
    throw StateError('dispute ${disp.statusCode} ${disp.body}');
  }
  createdD.add(dr!['id'].toString());
  await call('PATCH', '/rest/v1/order_disputes?id=eq.${dr['id']}', token: sellerJwt, body: {
    'seller_refund_percent': 100,
    'seller_offer_type': 'partial_refund',
  });
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  e2eSecret = env['FLEABER_STAGING_CRASH_INJECT_SECRET']?.trim();
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  buyerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  sellerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  buyerId = await sb.userIdForAccessToken(buyerJwt);
  sellerId = await sb.userIdForAccessToken(sellerJwt);
  final out = <String, dynamic>{};

  try {
    // Repro 2: partial then stripe refund
    final a = await paidOrder();
    final oidA = a['order_id'].toString();
    await offer100(oidA);
    final b0 = await bal(buyerId);
    final part = await call('POST', '/rest/v1/rpc/batata_process_partial_refund_dispute', token: buyerJwt, body: {
      'p_order_id': oidA,
      'p_refund_percent': 100,
    });
    final b1 = await bal(buyerId);
    final rf = await call('POST', '/functions/v1/refund-order', token: sellerJwt, body: {'order_id': oidA});
    final b2 = await bal(buyerId);
    out['repro2_partial_then_stripe'] = {
      'partial_http': part.statusCode,
      'partial_body': dec(part),
      'd_after_partial': b1 - b0,
      'refund_http': rf.statusCode,
      'refund_body': dec(rf),
      'd_after_stripe': b2 - b0,
      'wallet_kept_after_stripe': b2 - b1,
      'order': await order(oidA),
    };

    // Reverse: stripe refund first then partial
    final b = await paidOrder();
    final oidB = b['order_id'].toString();
    await offer100(oidB);
    final c0 = await bal(buyerId);
    final rfFirst = await call('POST', '/functions/v1/refund-order', token: sellerJwt, body: {'order_id': oidB});
    final partSecond = await call('POST', '/rest/v1/rpc/batata_process_partial_refund_dispute', token: buyerJwt, body: {
      'p_order_id': oidB,
      'p_refund_percent': 100,
    });
    final c1 = await bal(buyerId);
    out['repro_reverse_stripe_then_partial'] = {
      'refund_http': rfFirst.statusCode,
      'refund_body': dec(rfFirst),
      'partial_http': partSecond.statusCode,
      'partial_body': dec(partSecond),
      'dBuyer': c1 - c0,
      'order': await order(oidB),
    };
  } finally {
    for (final id in createdD) {
      await call('DELETE', '/rest/v1/order_disputes?id=eq.$id', service: true);
    }
    for (final id in createdO) {
      await call('DELETE', '/rest/v1/orders?id=eq.$id', service: true);
    }
    for (final id in createdP) {
      await call('DELETE', '/rest/v1/products?id=eq.$id', service: true);
    }
  }

  final f = File('tool/reports/REDTEAM_PARALLEL_C_20260830T0900_pass3.json');
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert({
    'FROZEN_AT': DateTime.now().toUtc().toIso8601String(),
    'AUDITOR': 'PARALLEL_C_DEEP_CASH',
    ...out,
  }));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('WROTE ${f.path}');
}
