// ignore_for_file: avoid_print
/// Residuais P2/P3 20260830 — dart run tool/sec_residuals_p2_p3_hostile.dart
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
      : method == 'GET'
          ? await http.get(Uri.parse(u), headers: h)
          : method == 'PATCH'
              ? await http.patch(
                  Uri.parse(u),
                  headers: h,
                  body: jsonEncode(body),
                )
              : await http.delete(Uri.parse(u), headers: h);
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

  // ---- P3 settle oracle ----
  final fakeSettle = await req(
    'GET',
    '$url/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_fake_oracle_$stamp',
    ANON,
  );
  final fakeTxt = '${fakeSettle['text']}';
  add(
    'P3_settle_no_stripe_oracle',
    (fakeSettle['http'] as int) >= 400 &&
        !fakeTxt.toLowerCase().contains('no such checkout') &&
        fakeTxt.contains('ainda não confirmado'),
    {'http': fakeSettle['http'], 'clip': fakeTxt.length > 120 ? fakeTxt.substring(0, 120) : fakeTxt},
  );

  // ---- P2 connect amount ≤0 ----
  final conn = await req(
    'POST',
    '$url/functions/v1/create-connect-account',
    SH,
    {'user_id': sellerId, 'amount': -100},
  );
  final connTxt = '${conn['text']}';
  add(
    'P2_connect_rejects_negative_amount',
    (conn['http'] as int) >= 400 &&
        connTxt.toLowerCase().contains('inválido'),
    {'http': conn['http'], 'clip': connTxt.length > 160 ? connTxt.substring(0, 160) : connTxt},
  );

  // ---- P2 shipping garbage fail-closed ----
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'Residual ship $stamp',
    'price': 12.0,
    'quantity': 3,
    'ref_code': 'RES-SHIP-$stamp',
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

  final oGarbage = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 12.0,
    'shipping_method': 'xyz-garbage-portes',
    'payment_method': 'Pagamento na app',
  });
  final oidG = idOf(oGarbage['body']);
  // Service may coerce seal — force garbage if needed
  if (oidG != null) {
    await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$oidG',
      SVC,
      {'shipping_method': 'xyz-garbage-portes'},
    );
    final cpi = await req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      BH,
      {
        'buyer_id': buyerId,
        'order_id': oidG,
        'shipping_method': 'hand',
      },
    );
    final cpiTxt = '${cpi['text']}';
    add(
      'P2_ship_garbage_fail_closed',
      (cpi['http'] as int) >= 400 &&
          (cpiTxt.contains('portes') || cpiTxt.contains('inválid')),
      {'http': cpi['http'], 'clip': cpiTxt.length > 180 ? cpiTxt.substring(0, 180) : cpiTxt},
    );
  } else {
    add('P2_ship_garbage_fail_closed', false, {'error': 'no order'});
  }

  // ---- P2 review: MB WAY review OK but NOT in public ratings ----
  final pOff = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'Residual rev $stamp',
    'price': 9.0,
    'quantity': 2,
    'ref_code': 'RES-REV-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pidR = idOf(pOff['body']);
  if (pidR != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/reviews?comment=eq.residual-mbway-$stamp', SVC);
      await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pidR', SVC);
      await req('DELETE', '$url/rest/v1/products?id=eq.$pidR', SVC);
    });
    final oOff = await req('POST', '$url/rest/v1/orders', BH, {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'product_id': pidR,
      'status': 'reserva_pendente',
      'quantity': 1,
      'price_total': 9.0,
      'shipping_method': 'hand',
      'payment_method': 'MB WAY',
    });
    final oidR = idOf(oOff['body']);
    if (oidR != null) {
      for (final st in ['pago', 'enviado', 'entregue']) {
        await req(
          'PATCH',
          '$url/rest/v1/orders?id=eq.$oidR',
          SH,
          {'status': st},
        );
      }
      final rev = await req('POST', '$url/rest/v1/reviews', BH, {
        'order_id': oidR,
        'buyer_id': buyerId,
        'target_id': sellerId,
        'stars': 5,
        'comment': 'residual-mbway-$stamp',
        'author_role': 'comprador',
        'purchase_verified': true,
      });
      final revRow = rev['body'] is List && (rev['body'] as List).isNotEmpty
          ? (rev['body'] as List).first as Map
          : (rev['body'] is Map ? rev['body'] as Map : {});
      final verified = revRow['purchase_verified'] == true;
      add(
        'P2_mbway_review_unverified_flag',
        (rev['http'] as int) == 201 && verified == false,
        {
          'http': rev['http'],
          'purchase_verified': revRow['purchase_verified'],
        },
      );
      final pub = await req(
        'GET',
        '$url/rest/v1/reviews_public_ratings?comment=eq.residual-mbway-$stamp&select=id,purchase_verified',
        ANON,
      );
      final pubEmpty = pub['body'] is List && (pub['body'] as List).isEmpty;
      add('P2_mbway_not_in_public_ratings', pubEmpty, {
        'http': pub['http'],
        'body': pub['body'],
      });
    } else {
      add('P2_mbway_review_unverified_flag', false, {'error': 'oid'});
      add('P2_mbway_not_in_public_ratings', false, {'error': 'oid'});
    }
  }

  // ---- P3 draw_seed column ----
  final raffle = await req(
    'GET',
    '$url/rest/v1/live_raffles?select=id,draw_seed&limit=1',
    BH,
  );
  final raffleTxt = '${raffle['text']}';
  add(
    'P3_draw_seed_not_selectable',
    (raffle['http'] as int) >= 400 ||
        raffleTxt.contains('draw_seed') && raffleTxt.contains('permission') ||
        raffleTxt.contains('42501') ||
        raffleTxt.contains('column'),
    {'http': raffle['http'], 'clip': raffleTxt.length > 160 ? raffleTxt.substring(0, 160) : raffleTxt},
  );

  for (final f in cleanup.reversed) {
    try {
      await f();
    } catch (_) {}
  }

  final pass = results.where((r) => r['ok'] == true).length;
  final fail = results.where((r) => r['ok'] != true).length;
  final outPath = 'tool/reports/sec_residuals_p2_p3_hostile_$stamp.json';
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
