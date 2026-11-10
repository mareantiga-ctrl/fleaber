// ignore_for_file: avoid_print
/// RT2035 grants + B-SHIP / B-BAG (Blind B 2045).
/// dart run tool/sec_rt2035_grants_ship_bag_hostile.dart
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

String clip(Object? v, [int n = 240]) {
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

bool denied(Map<String, dynamic> r) {
  final c = r['http'] as int;
  if (c == 401 || c == 403 || c == 404) return true;
  final t = '${r['body'] ?? r['text']}'.toLowerCase();
  return t.contains('permission') ||
      t.contains('42501') ||
      t.contains('not allow') ||
      t.contains('jwt') && c >= 400;
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
  final ANON = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
  };
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

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final cleanup = <Future Function()>[];
  final stamp = DateTime.now().millisecondsSinceEpoch;

  // ---- P1 LiveKit cleanup ----
  final lkAnon = await req(
    'POST',
    '$url/rest/v1/rpc/batata_invoke_livekit_egress_cleanup',
    ANON,
    <String, dynamic>{},
  );
  add('P1_livekit_cleanup_anon_denied', denied(lkAnon), {
    'http': lkAnon['http'],
    'body': clip(lkAnon['body']),
  });
  final lkBuyer = await req(
    'POST',
    '$url/rest/v1/rpc/batata_invoke_livekit_egress_cleanup',
    BH,
    <String, dynamic>{},
  );
  add('P1_livekit_cleanup_buyer_denied', denied(lkBuyer), {
    'http': lkBuyer['http'],
    'body': clip(lkBuyer['body']),
  });

  // ---- P2 backfill ----
  final bf = await req(
    'POST',
    '$url/rest/v1/rpc/batata_backfill_handle_suggestions',
    ANON,
    {'p_dry_run': false},
  );
  add('P2_backfill_anon_denied', denied(bf), {
    'http': bf['http'],
    'body': clip(bf['body']),
  });

  // ---- B-SHIP: order carrier + body hand → preço carrier ----
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'RT2035 ship $stamp',
    'price': 10.0,
    'quantity': 2,
    'ref_code': 'SHIP-$stamp',
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
    'price_total': 10.0,
    'shipping_method': 'Envio transportadora (€3.50)',
  });
  final oid1 = idOf(o1['body']);
  if (oid1 != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid1', SH, {
      'status': 'reservado',
    });
    // Garantir shipping na row (seller/buyer patch se INSERT não selou)
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid1', SVC, {
      'shipping_method': 'Envio transportadora (€3.50)',
    });
    final cpiHand = await req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      BH,
      {
        'buyer_id': buyerId,
        'order_id': oid1,
        'shipping_method': 'hand',
      },
    );
    final amt = cpiHand['body'] is Map
        ? int.tryParse('${(cpiHand['body'] as Map)['server_amount_cents'] ?? ''}')
        : null;
    // carrier 350 + items 1000 + prot ≈ 1483 (não hand ~1115)
    final shipOk = (cpiHand['http'] as int) == 200 &&
        amt != null &&
        amt >= 1400;
    add('SHIP_body_hand_ignored_uses_order_carrier', shipOk, {
      'http': cpiHand['http'],
      'server_amount_cents': amt,
      'body': clip(cpiHand['body']),
    });
  } else {
    add('SHIP_body_hand_ignored_uses_order_carrier', false, {'no_order': true});
  }

  // ---- B-BAG-DUP ----
  final o2 = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 10.0,
  });
  final oid2 = idOf(o2['body']);
  if (oid2 != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid2', SH, {
      'status': 'reservado',
    });
    final single = await req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      BH,
      {
        'buyer_id': buyerId,
        'order_id': oid2,
        'shipping_method': 'hand',
      },
    );
    final dup = await req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      BH,
      {
        'buyer_id': buyerId,
        'bag_checkout': true,
        'shipping_method': 'hand',
        'bag_lines': [
          {'order_id': oid2},
          {'order_id': oid2},
        ],
      },
    );
    final a1 = single['body'] is Map
        ? int.tryParse('${(single['body'] as Map)['server_amount_cents'] ?? ''}')
        : null;
    final a2 = dup['body'] is Map
        ? int.tryParse('${(dup['body'] as Map)['server_amount_cents'] ?? ''}')
        : null;
    add(
      'BAG_dup_order_id_same_as_single',
      a1 != null && a2 != null && a1 == a2 && (dup['http'] as int) == 200,
      {
        'single': a1,
        'dup': a2,
        'http': dup['http'],
        'dup_body': clip(dup['body'] ?? dup['text']),
      },
    );
  } else {
    add('BAG_dup_order_id_same_as_single', false, {'no_order': true});
  }

  for (final f in cleanup.reversed) {
    try {
      await f();
    } catch (_) {}
  }

  final pass = results.where((r) => r['ok'] == true).length;
  final fail = results.where((r) => r['ok'] != true).length;
  final outPath =
      'tool/reports/sec_rt2035_grants_ship_bag_hostile_$stamp.json';
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
