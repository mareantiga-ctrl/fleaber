// ignore_for_file: avoid_print
/// D0820 Costura v2 — dart run tool/sec_d0820_costura_v2_hostile.dart
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

  Future<String?> setupPaid({String ship = 'ctt'}) async {
    final paid = await req(
      'POST',
      '$url/functions/v1/sec-fase2-e2e-oversell',
      E2E,
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'probe': 'setup_paid_order',
        'initial_qty': 2,
        'shipping_method': ship,
      },
    );
    final id = idOf(paid['body']);
    if (id != null && ship.isNotEmpty) {
      await req('PATCH', '$url/rest/v1/orders?id=eq.$id', SVC, {
        'shipping_method': ship,
      });
    }
    return id;
  }

  // P1: pago → entregue blocked
  final o1 = await setupPaid(ship: 'ctt');
  add('fixture_o1', o1 != null, o1);
  if (o1 != null) {
    final r = await req('PATCH', '$url/rest/v1/orders?id=eq.$o1', BH, {
      'status': 'entregue',
    });
    final st = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$o1&select=status',
      SVC,
    ))['body']);
    add(
      'P1_pago_to_entregue_blocked',
      (r['http'] as int) >= 400 && '${st?['status']}' == 'pago',
      {'http': r['http'], 'status': st?['status'], 'body': r['body']},
    );
  }

  // P1: concluido → enviado reopen blocked
  final o2 = await setupPaid(ship: 'ctt');
  if (o2 != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$o2', SH, {
      'status': 'enviado',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.$o2', BH, {
      'status': 'concluido',
    });
    final reopen = await req('PATCH', '$url/rest/v1/orders?id=eq.$o2', SH, {
      'status': 'enviado',
    });
    final st = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$o2&select=status',
      SVC,
    ))['body']);
    add(
      'P1_seller_reopen_concluido_blocked',
      (reopen['http'] as int) >= 400 && '${st?['status']}' == 'concluido',
      {'http': reopen['http'], 'status': st?['status'], 'body': reopen['body']},
    );
  } else {
    add('P1_seller_reopen_concluido_blocked', false, 'no order');
  }

  // P1: pago → em_devolucao blocked
  final o3 = await setupPaid(ship: 'ctt');
  if (o3 != null) {
    final r = await req('PATCH', '$url/rest/v1/orders?id=eq.$o3', BH, {
      'status': 'em_devolucao',
    });
    final st = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$o3&select=status',
      SVC,
    ))['body']);
    add(
      'P1_pago_to_em_devolucao_blocked',
      (r['http'] as int) >= 400 && '${st?['status']}' == 'pago',
      {'http': r['http'], 'status': st?['status']},
    );
  } else {
    add('P1_pago_to_em_devolucao_blocked', false, 'no order');
  }

  // P1: wallet_release flag blocked
  final o4 = await setupPaid(ship: 'mao');
  if (o4 != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$o4', SVC, {
      'shipping_method': 'mao',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.$o4', BH, {
      'status': 'concluido',
    });
    final flag = await req('PATCH', '$url/rest/v1/orders?id=eq.$o4', BH, {
      'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String(),
    });
    add(
      'P1_wallet_release_flag_blocked',
      (flag['http'] as int) >= 400,
      {'http': flag['http'], 'body': flag['body']},
    );
    final af = await req('PATCH', '$url/rest/v1/orders?id=eq.$o4', BH, {
      'auto_feedback_processed_at': DateTime.now().toUtc().toIso8601String(),
    });
    add(
      'P1_auto_feedback_flag_blocked',
      (af['http'] as int) >= 400,
      {'http': af['http'], 'body': af['body']},
    );
  } else {
    add('P1_wallet_release_flag_blocked', false, 'no');
    add('P1_auto_feedback_flag_blocked', false, 'no');
  }

  // P2: bundle_id frozen after pago
  final o5 = await setupPaid(ship: 'mao');
  if (o5 != null) {
    final bun = await req('POST', '$url/rest/v1/product_bundles', SVC, {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'product_ids': <String>[],
      'subtotal_eur': 1,
      'discount_pct': 0,
      'discount_eur': 0,
      'total_eur': 1,
      'status': 'pending',
    });
    // May fail without products — use existing bundle or skip hitch with fake uuid
    final hitch = await req('PATCH', '$url/rest/v1/orders?id=eq.$o5', BH, {
      'bundle_id': '00000000-0000-4000-8000-000000000001',
    });
    add(
      'P2_bundle_id_frozen_after_pago',
      (hitch['http'] as int) >= 400,
      {'http': hitch['http'], 'body': hitch['body'], 'bun': bun['http']},
    );
  } else {
    add('P2_bundle_id_frozen_after_pago', false, 'no');
  }

  // Anti-reg: mão → concluido
  final o6 = await setupPaid(ship: 'mao');
  if (o6 != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$o6', SVC, {
      'shipping_method': 'mao',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.$o6', BH, {
      'status': 'concluido',
    });
    final st = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$o6&select=status',
      SVC,
    ))['body']);
    add('anti_reg_hand_concluido_ok', '${st?['status']}' == 'concluido', st);
  } else {
    add('anti_reg_hand_concluido_ok', false, 'no');
  }

  // Anti-reg: seller pago → enviado
  final o7 = await setupPaid(ship: 'ctt');
  if (o7 != null) {
    final env = await req('PATCH', '$url/rest/v1/orders?id=eq.$o7', SH, {
      'status': 'enviado',
    });
    final st = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$o7&select=status',
      SVC,
    ))['body']);
    add(
      'anti_reg_seller_enviado_ok',
      (env['http'] as int) < 300 && '${st?['status']}' == 'enviado',
      {'http': env['http'], 'status': st?['status']},
    );
    // Buyer concluido after enviado
    await req('PATCH', '$url/rest/v1/orders?id=eq.$o7', BH, {
      'status': 'concluido',
    });
    final st2 = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$o7&select=status',
      SVC,
    ))['body']);
    add(
      'anti_reg_carrier_concluido_after_enviado',
      '${st2?['status']}' == 'concluido',
      st2,
    );
  } else {
    add('anti_reg_seller_enviado_ok', false, 'no');
    add('anti_reg_carrier_concluido_after_enviado', false, 'no');
  }

  // Anti-reg: refund while pago
  final o8 = await setupPaid(ship: 'mao');
  if (o8 != null) {
    final ref = await req(
      'POST',
      '$url/functions/v1/refund-order',
      SH,
      {'order_id': o8},
    );
    add(
      'anti_reg_refund_while_pago_ok',
      (ref['http'] as int) == 200,
      {'http': ref['http'], 'body': ref['body']},
    );
  } else {
    add('anti_reg_refund_while_pago_ok', false, 'no');
  }

  final fail = results.where((r) => r['ok'] != true).length;
  stdout.writeln('\n=== ${results.length - fail}/${results.length} PASS ===');
  exit(fail == 0 ? 0 : 1);
}
