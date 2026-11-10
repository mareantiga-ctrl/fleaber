// ignore_for_file: avoid_print
/// S2-P0 settle replay + BI-SHIP-01 shipping seal.
/// dart run tool/sec_s2_p0_settle_ship_hostile.dart
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
          ? await http.patch(Uri.parse(u), headers: h, body: jsonEncode(body))
          : method == 'GET'
              ? await http.get(Uri.parse(u), headers: h)
              : await http.delete(Uri.parse(u), headers: h);
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
  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
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
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final cleanup = <Future Function()>[];

  // ---- BI-SHIP: freeze shipping ----
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'S2 ship $stamp',
    'price': 15.0,
    'quantity': 3,
    'ref_code': 'S2SHIP-$stamp',
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
    'price_total': 15.0,
    'shipping_method': 'Envio transportadora (€3.50)',
  });
  final oid1 = idOf(o1['body']);
  add('fixture_order_carrier', oid1 != null, {'id': oid1});
  if (oid1 != null) {
    final patchHand = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$oid1',
      BH,
      {'shipping_method': 'hand'},
    );
    final after = await req(
      'GET',
      '$url/rest/v1/orders?select=id,shipping_method&id=eq.$oid1',
      SVC,
    );
    final ship = after['body'] is List && (after['body'] as List).isNotEmpty
        ? '${(after['body'] as List).first['shipping_method']}'
        : '';
    final frozen = ship.toLowerCase().contains('transportadora') ||
        ship.toLowerCase().contains('carrier');
    add('SHIP_patch_hand_frozen', frozen, {
      'patch_http': patchHand['http'],
      'shipping_method': ship,
    });

    final patchEmpty = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$oid1',
      BH,
      {'shipping_method': ''},
    );
    final after2 = await req(
      'GET',
      '$url/rest/v1/orders?select=shipping_method&id=eq.$oid1',
      SVC,
    );
    final ship2 = after2['body'] is List && (after2['body'] as List).isNotEmpty
        ? '${(after2['body'] as List).first['shipping_method']}'
        : '';
    add(
      'SHIP_patch_empty_frozen',
      ship2.toLowerCase().contains('transportadora') ||
          ship2.toLowerCase().contains('carrier'),
      {'patch_http': patchEmpty['http'], 'shipping_method': ship2},
    );

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
    final amt = cpi['body'] is Map
        ? int.tryParse('${(cpi['body'] as Map)['server_amount_cents'] ?? ''}')
        : null;
    // 1500 + 350 + prot ≈ 2008 (não hand ~1640)
    add('SHIP_checkout_stays_carrier', (cpi['http'] as int) == 200 && amt != null && amt >= 1900, {
      'http': cpi['http'],
      'server_amount_cents': amt,
    });

    // Bag: duas lines carrier + body hand → portes selados (não mão).
    final prodB = await req('POST', '$url/rest/v1/products', SVC, {
      'seller_id': sellerId,
      'title': 'S2 ship B $stamp',
      'price': 10.0,
      'quantity': 2,
      'ref_code': 'S2SHIPB-$stamp',
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final pidB = idOf(prodB['body']);
    if (pidB != null) {
      cleanup.add(() async {
        await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pidB', SVC);
        await req('DELETE', '$url/rest/v1/products?id=eq.$pidB', SVC);
      });
      final o2 = await req('POST', '$url/rest/v1/orders', BH, {
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'product_id': pidB,
        'status': 'reserva_pendente',
        'quantity': 1,
        'price_total': 10.0,
        'shipping_method': 'Envio transportadora (€3.50)',
      });
      final oid2 = idOf(o2['body']);
      if (oid2 != null) {
        final bagCpi = await req(
          'POST',
          '$url/functions/v1/create-payment-intent',
          BH,
          {
            'buyer_id': buyerId,
            'bag_checkout': true,
            'shipping_method': 'hand',
            'bag_lines': [
              {'order_id': oid1},
              {'order_id': oid2},
            ],
          },
        );
        final bagAmt = bagCpi['body'] is Map
            ? int.tryParse(
                '${(bagCpi['body'] as Map)['server_amount_cents'] ?? ''}',
              )
            : null;
        // 15+10 com desconto conjunto ~10% → itens 2250 + carrier 350 + prot ≈ 2795.
        // Mão seria ~2428. Indep atacava com body hand a baixar portes.
        add(
          'SHIP_bag_uses_sealed_carrier',
          (bagCpi['http'] as int) == 200 &&
              bagAmt != null &&
              bagAmt >= 2700,
          {
            'http': bagCpi['http'],
            'server_amount_cents': bagAmt,
          },
        );
      } else {
        add('SHIP_bag_uses_sealed_carrier', false, {'error': 'oid2'});
      }
    } else {
      add('SHIP_bag_uses_sealed_carrier', false, {'error': 'pidB'});
    }
  }

  // ---- S2-P0: hosted Checkout já pago + GET settle replay (prova browser/check) ----
  // Stripe adia PI até ao hosted pay — o probe Edge não confirma Session aberta.
  // Prova canónica: tool/sec_s2_p0_settle_replay_check.dart após pagar Session TEST.
  final p0Setup = File('tool/reports/sec_s2_p0_settle_setup_1788074173140.json');
  if (p0Setup.existsSync()) {
    final setup =
        jsonDecode(await p0Setup.readAsString()) as Map<String, dynamic>;
    final oid = '${setup['order_id']}';
    final sid = '${setup['checkoutSessionId']}';
    final chk = await Process.run(
      'dart',
      ['run', 'tool/sec_s2_p0_settle_replay_check.dart', oid, sid],
      workingDirectory: Directory.current.path,
    );
    final out = '${chk.stdout}\n${chk.stderr}';
    add(
      'P0_settle_replay_keeps_pago',
      chk.exitCode == 0 && out.contains('PASS P0_settle_replay'),
      {
        'exit': chk.exitCode,
        'clip': clip(out.replaceAll('\n', ' | '), 400),
      },
    );
  } else {
    add('P0_settle_replay_keeps_pago', false, {
      'error': 'missing setup json — run settle_setup_once + pay + check',
    });
  }

  for (final f in cleanup.reversed) {
    try {
      await f();
    } catch (_) {}
  }

  final pass = results.where((r) => r['ok'] == true).length;
  final fail = results.where((r) => r['ok'] != true).length;
  final outPath = 'tool/reports/sec_s2_p0_settle_ship_hostile_$stamp.json';
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
