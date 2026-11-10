// ignore_for_file: avoid_print
/// REAUDIT-N1 / P2-03 — portes: método allowlist vs bypass `shipping` numérico.
/// Staging only. Uso: dart run tool/sec_reaudit_n1_shipping_hostile.dart [before|after]
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> postJson(
  String url,
  Map<String, String> headers,
  Map<String, dynamic> body,
) async {
  final r = await http.post(
    Uri.parse(url),
    headers: headers,
    body: jsonEncode(body),
  );
  dynamic parsed;
  try {
    parsed = jsonDecode(r.body);
  } catch (_) {
    parsed = r.body;
  }
  return {
    'http': r.statusCode,
    'server_amount_cents': parsed is Map ? parsed['server_amount_cents'] : null,
    'shipping_cents': parsed is Map
        ? (parsed['shipping_cents'] ?? parsed['shippingCents'])
        : null,
    'error': parsed is Map ? parsed['error'] : null,
  };
}

void main(List<String> args) async {
  final phase = (args.isNotEmpty ? args.first : 'after').toLowerCase();
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: só staging');
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
  };

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final prodRes = await http.post(
    Uri.parse('$url/rest/v1/products'),
    headers: SH,
    body: jsonEncode({
      'seller_id': sellerId,
      'title': 'REAUDIT-N1 ship $stamp',
      'price': 6.66,
      'quantity': 20,
      'list_on_marketplace': false,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    }),
  );
  final prod = jsonDecode(prodRes.body);
  final prodId = (prod is List && prod.isNotEmpty)
      ? prod.first['id']?.toString()
      : (prod is Map ? prod['id']?.toString() : null);
  if (prodId == null) {
    stderr.writeln('product fail ${prodRes.statusCode} ${prodRes.body}');
    exit(1);
  }

  final ordRes = await http.post(
    Uri.parse('$url/rest/v1/orders'),
    headers: BH,
    body: jsonEncode({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': prodId,
      'quantity': 1,
      'price_total': 6.66,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    }),
  );
  final ord = jsonDecode(ordRes.body);
  final oid = (ord is List && ord.isNotEmpty)
      ? ord.first['id']?.toString()
      : (ord is Map ? ord['id']?.toString() : null);
  if (oid == null) {
    stderr.writeln('order fail ${ordRes.statusCode} ${ordRes.body}');
    exit(1);
  }

  Future<Map<String, dynamic>> cpi(Map<String, dynamic> extra) {
    return postJson(
      '$url/functions/v1/create-payment-intent',
      BH,
      {
        'buyer_id': buyerId,
        'order_id': oid,
        ...extra,
      },
    );
  }

  // items 666 + ship + prot(0.65+5%(items+ship))
  // mão: 764 · carrier: 1132
  const expectHand = 764;
  const expectCarrier = 1132;

  final cases = <Map<String, dynamic>>[
    {
      'id': 'garbage_plus_shipping_0',
      'body': {'shipping_method': 'free_shipping_please', 'shipping': 0},
      'expect_http': 400,
    },
    {
      'id': 'garbage_plus_shipping_350',
      'body': {'shipping_method': 'whatever', 'shipping': 350},
      'expect_http': 400,
    },
    {
      'id': 'garbage_plus_shipping_1',
      'body': {'shipping_method': 'whatever', 'shipping': 1},
      'expect_http': 400,
    },
    {
      'id': 'empty_plus_shipping_0',
      'body': {'shipping_method': '', 'shipping': 0},
      'expect_http': 400,
    },
    {
      'id': 'euro0_plus_shipping_0',
      'body': {'shipping_method': '€0', 'shipping': 0},
      'expect_http': 400,
    },
    {
      'id': 'gratis_plus_shipping_0',
      'body': {'shipping_method': 'gratis', 'shipping': 0},
      'expect_http': 400,
    },
    {
      'id': 'hand_plus_shipping_350',
      'body': {'shipping_method': 'hand', 'shipping': 350},
      'expect_http': 200,
      'expect_amount': expectHand,
    },
    {
      'id': 'mao_plus_shipping_350',
      'body': {'shipping_method': 'entrega em mão', 'shipping': 350},
      'expect_http': 200,
      'expect_amount': expectHand,
    },
    {
      'id': 'flutter_hand_omit_shipping',
      'body': {'shipping_method': 'Entrega em Mão (€0.00)'},
      'expect_http': 200,
      'expect_amount': expectHand,
    },
    {
      'id': 'transportadora_plus_shipping_0',
      'body': {'shipping_method': 'transportadora', 'shipping': 0},
      'expect_http': 200,
      'expect_amount': expectCarrier,
    },
    {
      'id': 'carrier_plus_shipping_0',
      'body': {'shipping_method': 'carrier', 'shipping': 0},
      'expect_http': 200,
      'expect_amount': expectCarrier,
    },
    {
      'id': 'flutter_carrier_omit_shipping',
      'body': {'shipping_method': 'Envio Transportadora (€3.50)'},
      'expect_http': 200,
      'expect_amount': expectCarrier,
    },
    {
      'id': 'EUR0_alone',
      'body': {'shipping_method': 'EUR0'},
      'expect_http': 400,
    },
    {
      'id': 'only_shipping_0_no_method',
      'body': {'shipping': 0},
      'expect_http': 400,
    },
    {
      'id': 'only_shipping_350_no_method',
      'body': {'shipping': 350},
      'expect_http': 400,
    },
  ];

  final results = <Map<String, dynamic>>[];
  var pass = 0;
  var fail = 0;
  for (final c in cases) {
    final res = await cpi(Map<String, dynamic>.from(c['body'] as Map));
    final expectHttp = c['expect_http'] as int;
    final expectAmt = c['expect_amount'] as int?;
    final httpOk = res['http'] == expectHttp;
    final amtOk = expectAmt == null ||
        (res['http'] == 200 && res['server_amount_cents'] == expectAmt);
    final ok = httpOk && amtOk;
    if (ok) {
      pass++;
    } else {
      fail++;
    }
    results.add({
      'id': c['id'],
      'ok': ok,
      'expect_http': expectHttp,
      'expect_amount': expectAmt,
      'got': res,
    });
    stdout.writeln(
      '${ok ? "PASS" : "FAIL"} ${c['id']}: http=${res['http']} amt=${res['server_amount_cents']} (expect $expectHttp${expectAmt != null ? "/$expectAmt" : ""})',
    );
  }

  await http.delete(
    Uri.parse('$url/rest/v1/orders?product_id=eq.$prodId'),
    headers: SVC,
  );
  await http.delete(
    Uri.parse('$url/rest/v1/products?id=eq.$prodId'),
    headers: SVC,
  );

  final evidence = {
    'test': 'REAUDIT-N1_P2-03_shipping_numeric_bypass',
    'phase': phase,
    'at': DateTime.now().toUtc().toIso8601String(),
    'staging_ref': 'fxdknzrqjenzqcvnwqqq',
    'product_price_eur': 6.66,
    'expect_hand_total': expectHand,
    'expect_carrier_total': expectCarrier,
    'pass': pass,
    'fail': fail,
    'ok': fail == 0,
    'cases': results,
  };
  final out =
      'tool/reports/HARDENING_REAUDIT_N1_SHIPPING_${phase.toUpperCase()}.json';
  await File(out).writeAsString(
    const JsonEncoder.withIndent('  ').convert(evidence),
  );
  stdout.writeln('evidence -> $out ($pass pass / $fail fail)');
  // Before: expect some FAIL (bypass). After: all PASS.
  if (phase == 'before') {
    exit(0);
  }
  exit(fail == 0 ? 0 : 1);
}
