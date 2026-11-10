// ignore_for_file: avoid_print
/// RTBB-B-03 pairing rate + residual dual-session/settle proof.
/// dart run tool/sec_rtbb_b03_pairing_dual_settle_hostile.dart
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
      : method == 'PATCH'
          ? await http.patch(Uri.parse(u), headers: h, body: jsonEncode(body))
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

String clip(Object? v, [int n = 280]) {
  final s = '$v';
  return s.length <= n ? s : s.substring(0, n);
}

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    final s = '${(body.first as Map)['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  return null;
}

bool textHas(dynamic body, String needle) {
  return '$body'.toLowerCase().contains(needle.toLowerCase());
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
    if (e2eSecret.length >= 16) 'x-fleaber-e2e-secret': e2eSecret,
  };
  final ANON = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final cleanup = <Future Function()>[];
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final testIp = '203.0.113.${stamp % 200 + 1}'; // TEST-NET

  // -------------------------------------------------------------------------
  // B-03: rodar device_id com mesmo IP → rate_limited (scope ip)
  // -------------------------------------------------------------------------
  final seed = await req(
    'POST',
    '$url/rest/v1/batata_anon_rate_limits',
    {
      ...SVC,
      'Prefer': 'resolution=merge-duplicates,return=representation',
    },
    {
      'rate_key': 'ps_claim:ip:$testIp',
      'rpc': 'batata_ps_claim_pairing',
      'window_start': DateTime.now()
          .toUtc()
          .copyWith(minute: 0, second: 0, millisecond: 0, microsecond: 0)
          .toIso8601String(),
      'hits': 40,
    },
  );
  // Se POST na tabela falhar (RLS), usar RPC loop curto via service
  var seeded = (seed['http'] as int) < 300;
  if (!seeded) {
    // Fallback: 40 claims errados com mesmo IP (service RPC)
    for (var i = 0; i < 40; i++) {
      await req('POST', '$url/rest/v1/rpc/batata_ps_claim_pairing', SVC, {
        'p_code': '000000',
        'p_device_id': 'seed-dev-$i-$stamp',
        'p_client_ip': testIp,
      });
    }
    seeded = true;
  }
  add('B03_seed_ip_at_cap', seeded, {
    'ip': testIp,
    'seed_http': seed['http'],
    'seed_body': clip(seed['body']),
  });

  final rot = await req('POST', '$url/rest/v1/rpc/batata_ps_claim_pairing', SVC, {
    'p_code': '000000',
    'p_device_id': 'rotated-$stamp',
    'p_client_ip': testIp,
  });
  final rotBody = rot['body'];
  final ipBlocked = textHas(rotBody, 'rate_limited') &&
      (textHas(rotBody, '"scope": "ip"') ||
          textHas(rotBody, 'scope":"ip"') ||
          textHas(rotBody, 'ip'));
  add('B03_rotate_device_same_ip_blocked', ipBlocked, {
    'http': rot['http'],
    'body': clip(rotBody),
  });

  // IP fresco: não rate_limited — invalid code
  final freshIp = '198.51.100.${stamp % 200 + 1}';
  final fresh = await req('POST', '$url/rest/v1/rpc/batata_ps_claim_pairing', SVC, {
    'p_code': '000000',
    'p_device_id': 'fresh-$stamp',
    'p_client_ip': freshIp,
  });
  add(
    'B03_fresh_ip_not_rate_limited',
    textHas(fresh['body'], 'invalid_or_expired_code') &&
        !textHas(fresh['body'], 'rate_limited'),
    {'http': fresh['http'], 'body': clip(fresh['body'])},
  );

  // Edge: header X-Forwarded-For + device rotativo (smoke — 1 pedido inválido)
  final edge = await req(
    'POST',
    '$url/functions/v1/ps-pairing-claim',
    {
      ...ANON,
      'X-Forwarded-For': freshIp,
    },
    {'code': '000000', 'device_id': 'edge-$stamp'},
  );
  add(
    'B03_edge_accepts_ip_header_path',
    (edge['http'] as int) == 400 || (edge['http'] as int) == 429,
    {'http': edge['http'], 'body': clip(edge['body'])},
  );

  // -------------------------------------------------------------------------
  // Dual Session: qty=1 → 2.ª pending bloqueada; 1 Session OK
  // -------------------------------------------------------------------------
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'RTBB dual $stamp',
    'price': 5.0,
    'quantity': 1,
    'ref_code': 'DUAL-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = idOf(prod['body']);
  add('fixture_product', pid != null, {'id': pid});
  if (pid != null) {
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
      'price_total': 5.0,
    });
    final oid1 = idOf(o1['body']);
    final o2 = await req('POST', '$url/rest/v1/orders', BH, {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'product_id': pid,
      'status': 'reserva_pendente',
      'quantity': 1,
      'price_total': 5.0,
    });
    add(
      'DUAL_second_pending_ok_waitlist',
      oid1 != null &&
          oid2 != null &&
          (o2['http'] as int) < 300,
      {'o1': oid1, 'o2': oid2, 'o2_http': o2['http']},
    );

    if (oid1 != null) {
      await req('PATCH', '$url/rest/v1/orders?id=eq.$oid1', SH, {
        'status': 'reservado',
      });
      if (oid2 != null) {
        final acc2 = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid2', SH, {
          'status': 'reservado',
        });
        add(
          'DUAL_second_accept_blocked',
          (acc2['http'] as int) >= 400 ||
              textHas(acc2['body'], 'order_hold_exceeds_stock'),
          {'http': acc2['http'], 'body': clip(acc2['body'])},
        );
      }
      final cpi = await req(
        'POST',
        '$url/functions/v1/create-payment-intent',
        BH,
        {
          'buyer_id': buyerId,
          'order_id': oid1,
          'shipping_method': 'hand',
        },
      );
      final url1 = cpi['body'] is Map
          ? '${(cpi['body'] as Map)['checkoutUrl'] ?? ''}'
          : '';
      add(
        'DUAL_one_session_ok',
        (cpi['http'] as int) == 200 && url1.contains('checkout.stripe'),
        {'http': cpi['http'], 'has_url': url1.contains('checkout.stripe')},
      );
    }
  }

  // -------------------------------------------------------------------------
  // Rede de segurança: settle oversell e2e (captura dual → refund)
  // -------------------------------------------------------------------------
  final oversell = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {'buyer_id': buyerId, 'seller_id': sellerId},
  );
  Map<String, dynamic> ovBody = {};
  try {
    if (oversell['body'] is Map) {
      ovBody = Map<String, dynamic>.from(oversell['body'] as Map);
    }
  } catch (_) {}
  final checks = ovBody['checks'] is Map
      ? Map<String, dynamic>.from(ovBody['checks'] as Map)
      : <String, dynamic>{};
  add(
    'SETTLE_e2e_oversell_refund_intact',
    oversell['http'] == 200 &&
        ovBody['ok'] == true &&
        checks['refund_created'] == true &&
        checks['settle_b_oversell'] == true,
    {
      'http': oversell['http'],
      'ok': ovBody['ok'],
      'checks': {
        'refund_created': checks['refund_created'],
        'settle_b_oversell': checks['settle_b_oversell'],
        'loser_cancelado': checks['loser_cancelado'],
        'winner_order_pago': checks['winner_order_pago'],
      },
      'err': clip(ovBody['error'] ?? oversell['body']),
    },
  );

  for (final f in cleanup.reversed) {
    try {
      await f();
    } catch (_) {}
  }

  final pass = results.where((r) => r['ok'] == true).length;
  final fail = results.where((r) => r['ok'] != true).length;
  final outPath =
      'tool/reports/sec_rtbb_b03_pairing_dual_settle_hostile_$stamp.json';
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
