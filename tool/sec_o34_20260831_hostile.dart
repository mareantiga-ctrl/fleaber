// ignore_for_file: avoid_print
/// O34 clears — dart run tool/sec_o34_20260831_hostile.dart
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
    final nested = m['order'];
    if (nested is Map) {
      final oid = '${nested['id'] ?? ''}'.trim();
      if (oid.isNotEmpty && oid != 'null') return oid;
    }
  }
  return idOf(body);
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: not staging');
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
  final oid = orderIdFromE2E(paid['body']);
  add('fixture_paid', oid != null && oid.isNotEmpty && oid != 'null', {'oid': oid, 'http': paid['http']});
  if (oid == null || oid.isEmpty || oid == 'null') {
    stderr.writeln('ABORT no paid order');
    exit(1);
  }

  await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SVC, {
    'shipping_method': 'mao',
    'payment_method': 'pagamento na app',
  });
  await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {'status': 'enviado'});
  await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {'status': 'concluido'});

  await req('POST', '$url/rest/v1/order_disputes', BH, {
    'order_id': oid,
    'buyer_id': buyerId,
    'reason': 'nao_corresponde',
    'description': 'O34 devolvida guard $stamp',
    'proof_photos': <String>[],
    'status': 'aberta',
    'current_turn': 'vendedor',
  });
  await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {'status': 'pedido_devolucao'});
  await req('PATCH', '$url/rest/v1/order_disputes?order_id=eq.$oid', SH, {
    'seller_offer_type': 'return',
    'status': 'respondida_vendedor',
  });
  await req('PATCH', '$url/rest/v1/order_disputes?order_id=eq.$oid', BH, {
    'buyer_decision': 'accepted_return',
  });
  await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {'status': 'em_devolucao'});
  await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {'status': 'devolucao_entregue'});

  final devNoRefund = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {
    'status': 'devolvida',
  });
  final ordBlocked = firstMap(
    (await req('GET', '$url/rest/v1/orders?id=eq.$oid&select=status,stripe_refund_id', SVC))['body'],
  );
  add(
    'O3_devolvida_without_stripe_blocked',
    (devNoRefund['http'] as int) >= 400 &&
        '${ordBlocked?['status']}' != 'devolvida',
    {
      'http': devNoRefund['http'],
      'body': devNoRefund['body'],
      'order': ordBlocked,
    },
  );

  final oid2Resp = await req(
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
  final oid2 = orderIdFromE2E(oid2Resp['body']);
  if (oid2 != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid2', SVC, {
      'payment_method': 'pagamento na app',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid2', SH, {'status': 'enviado'});
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid2', BH, {'status': 'concluido'});
    await req('POST', '$url/rest/v1/order_disputes', BH, {
      'order_id': oid2,
      'buyer_id': buyerId,
      'reason': 'nao_corresponde',
      'description': 'O34 partial 100 $stamp',
      'proof_photos': <String>[],
      'status': 'aberta',
      'current_turn': 'vendedor',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid2', BH, {'status': 'pedido_devolucao'});
    await req('PATCH', '$url/rest/v1/order_disputes?order_id=eq.$oid2', SH, {
      'seller_refund_percent': 100,
      'seller_offer_type': 'partial_refund',
      'seller_offer_set_by': sellerId,
      'status': 'respondida_vendedor',
    });
    final rpc100 = await req(
      'POST',
      '$url/rest/v1/rpc/batata_process_partial_refund_dispute',
      BH,
      {'p_order_id': oid2, 'p_refund_percent': 100},
    );
    final ord2 = firstMap(
      (await req(
        'GET',
        '$url/rest/v1/orders?id=eq.$oid2&select=wallet_refund_processed_at,stripe_refund_id',
        SVC,
      ))['body'],
    );
    add(
      'O4_partial_100_wallet_blocked',
      (rpc100['http'] as int) >= 400 &&
          ord2?['wallet_refund_processed_at'] == null,
      {'http': rpc100['http'], 'body': rpc100['body'], 'order': ord2},
    );
  } else {
    add('O4_partial_100_wallet_blocked', false, {
      'fixture_http': oid2Resp['http'],
      'fixture_body': oid2Resp['body'],
    });
  }

  final fails = results.where((r) => r['ok'] != true).length;
  print('--- O34 hostile ${results.length - fails}/${results.length} PASS ---');
  exit(fails > 0 ? 1 : 0);
}
