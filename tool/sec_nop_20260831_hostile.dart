// ignore_for_file: avoid_print
/// NOP clears — dart run tool/sec_nop_20260831_hostile.dart
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

  // 2nd seller (spoof actor) — reuse buyer as "not owner" if no s2; try create session
  final s2Email = e['LIVE_OPS_TEST_BUYER2_EMAIL'] ?? e['LIVE_OPS_TEST_SELLER2_EMAIL'];
  final s2Pass = e['LIVE_OPS_TEST_BUYER2_PASSWORD'] ?? e['LIVE_OPS_TEST_SELLER2_PASSWORD'];
  String? s2Tok;
  String? s2Id;
  if (s2Email != null && s2Pass != null && s2Email.isNotEmpty) {
    try {
      s2Tok = await sb.signIn(email: s2Email, password: s2Pass);
      final me = await req('GET', '$url/auth/v1/user', {
        'apikey': anon,
        'Authorization': 'Bearer $s2Tok',
      });
      s2Id = (me['body'] is Map) ? '${(me['body'] as Map)['id']}' : null;
    } catch (_) {}
  }

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

  // ---- N-P0: spoof seller_id on live bag ----
  final live = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'title': 'NOP live $stamp',
    'status': 'live',
    'is_active': true,
  });
  final liveId = idOf(live['body']);
  final item = await req('POST', '$url/rest/v1/live_items', SVC, {
    'live_id': liveId,
    'ref_code': 'NOP$stamp',
    'title': 'NOP item $stamp',
    'price': 5.0,
    'quantity': 1,
    'status': 'available',
    'is_active': true,
  });
  final itemId = idOf(item['body']);
  add('fixture_live', liveId != null && itemId != null, {
    'live': liveId,
    'item': itemId,
    'item_http': item['http'],
    'item_body': item['body'],
  });
  if (itemId == null) {
    stderr.writeln('ABORT no live_item');
    exit(1);
  }

  if (s2Tok != null && s2Id != null && s2Id != sellerId) {
    final S2H = {
      'apikey': anon,
      'Authorization': 'Bearer $s2Tok',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
    final spoof = await req('POST', '$url/rest/v1/live_reservation_requests', S2H, {
      'live_id': liveId,
      'live_item_id': itemId,
      'seller_id': s2Id,
      'buyer_id': s2Id,
      'status': 'accepted',
      'requested_qty': 1,
      'source': 'fleaber_live',
    });
    final row = firstMap(spoof['body']);
    final st = '${row?['status'] ?? ''}';
    final sid = '${row?['seller_id'] ?? ''}';
    add(
      'N_P0_spoof_not_accepted',
      (spoof['http'] as int) >= 400 ||
          (st == 'pending' && sid == sellerId),
      {'http': spoof['http'], 'status': st, 'seller_id': sid},
    );
  } else {
    // fallback: buyer spoof as seller_id=self
    final spoof = await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
      'live_id': liveId,
      'live_item_id': itemId,
      'seller_id': buyerId,
      'buyer_id': buyerId,
      'status': 'accepted',
      'requested_qty': 1,
      'source': 'fleaber_live',
    });
    final row = firstMap(spoof['body']);
    add(
      'N_P0_spoof_not_accepted',
      (spoof['http'] as int) >= 400 ||
          ('${row?['status']}' == 'pending' && '${row?['seller_id']}' == sellerId),
      {'http': spoof['http'], 'row': row},
    );
  }

  // ---- N-P2 stop_egress foreign ----
  final stop = await req(
    'POST',
    '$url/functions/v1/livekit-mux-publish',
    SH,
    {
      'step': 'stop_egress',
      'live_id': liveId,
      'egress_id': 'EG_FOREIGN_NOP_$stamp',
    },
  );
  add(
    'N_P2_stop_foreign_blocked',
    (stop['http'] as int) >= 400,
    {'http': stop['http'], 'body': stop['body']},
  );

  // ---- O-P1 abort return ----
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
  final oid = idOf(paid['body']) ??
      '${(paid['body'] is Map ? (paid['body'] as Map)['order_id'] : '')}'.trim();
  if (oid.isNotEmpty && oid != 'null') {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SVC, {
      'shipping_method': 'mao',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {'status': 'enviado'});
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {'status': 'concluido'});
    final dispIns = await req('POST', '$url/rest/v1/order_disputes', BH, {
      'order_id': oid,
      'buyer_id': buyerId,
      'reason': 'nao_corresponde',
      'description': 'NOP abort test disputa prova label wrap $stamp.',
      'proof_photos': <String>[],
      'status': 'aberta',
      'current_turn': 'vendedor',
    });
    // Forçar ciclo de devolução (serviço) para isolar o guard O-P1
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SVC, {
      'status': 'pedido_devolucao',
    });
    final abort = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {
      'status': 'enviado',
    });
    final after = firstMap(
      (await req('GET', '$url/rest/v1/orders?id=eq.$oid&select=status', SVC))['body'],
    );
    add(
      'O_P1_abort_return_blocked',
      (abort['http'] as int) >= 400 && '${after?['status']}' == 'pedido_devolucao',
      {
        'http': abort['http'],
        'status': after?['status'],
        'disp': dispIns['http'],
        'abort_body': abort['body'],
      },
    );

    final proof = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {
      'proof_url': 'https://evil.example/fake.pdf',
    });
    add('O_P2_proof_evil_blocked', (proof['http'] as int) >= 400, {
      'http': proof['http'],
    });

    final did = idOf(dispIns['body']) ??
        idOf(
          (await req(
            'GET',
            '$url/rest/v1/order_disputes?order_id=eq.$oid&select=id&limit=1',
            SVC,
          ))['body'],
        );
    final disputeId = did ??
        idOf(
          (await req('POST', '$url/rest/v1/order_disputes', SVC, {
            'order_id': oid,
            'buyer_id': buyerId,
            'reason': 'nao_corresponde',
            'description': 'NOP label wrap disputa prova $stamp.',
            'proof_photos': <String>[],
            'status': 'aberta',
            'current_turn': 'vendedor',
          }))['body'],
        );
    if (disputeId != null) {
      final wrap = await req(
        'PATCH',
        '$url/rest/v1/order_disputes?id=eq.$disputeId',
        BH,
        {'return_label_url': 'https://fleaber.app/https://evil.example/x'},
      );
      add('O_P2_label_wrap_blocked', (wrap['http'] as int) >= 400, {
        'http': wrap['http'],
        'body': wrap['body'],
      });
    } else {
      add('O_P2_label_wrap_blocked', false, 'no dispute');
    }
  } else {
    add('O_P1_abort_return_blocked', false, paid['body']);
    add('O_P2_proof_evil_blocked', false, 'no order');
    add('O_P2_label_wrap_blocked', false, 'no order');
  }

  await req('PATCH', '$url/rest/v1/lives?id=eq.$liveId', SVC, {
    'status': 'ended',
    'is_active': false,
  });

  final failed = results.where((r) => r['ok'] != true).toList();
  print('\n=== ${results.length - failed.length}/${results.length} PASS ===');
  if (failed.isNotEmpty) {
    stderr.writeln('FAILED: ${failed.map((e) => e['id']).join(', ')}');
    exit(1);
  }
}
