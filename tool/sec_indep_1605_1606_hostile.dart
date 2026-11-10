// ignore_for_file: avoid_print
/// Indep 1605/1606 P2/P3 — dart run tool/sec_indep_1605_1606_hostile.dart
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

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;

  // ---- P2 events INSERT denied ----
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': '1606 $stamp',
    'price': 12.5,
    'quantity': 3,
    'ref_code': 'I1606-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = idOf(prod['body']);
  final ord = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 12.5,
    'shipping_method': 'mao',
    'payment_method': 'Pagamento na app',
  });
  final oid = idOf(ord['body']);
  add('fixture_order', oid != null, {'id': oid});

  final evIns = await req('POST', '$url/rest/v1/stripe_checkout_events', BH, {
    'order_id': oid,
    'buyer_id': buyerId,
    'event': 'refund_created',
    'session_id': 'cs_test_fake_$stamp',
    'detail': 'hostile',
  });
  add(
    'P2_events_insert_denied',
    (evIns['http'] as int) >= 400,
    {'http': evIns['http'], 'body': evIns['body']},
  );

  // ---- P3 money PATCH raises ----
  final patch = await req(
    'PATCH',
    '$url/rest/v1/orders?id=eq.$oid',
    BH,
    {
      'amount_paid_cents': 1,
      'stripe_payment_intent_id': 'pi_fake_$stamp',
      'status': 'pago',
    },
  );
  add(
    'P3_money_patch_rejected',
    (patch['http'] as int) >= 400,
    {'http': patch['http'], 'body': patch['body']},
  );
  final observe = await req(
    'GET',
    '$url/rest/v1/orders?id=eq.$oid&select=status,amount_paid_cents,stripe_payment_intent_id',
    SVC,
  );
  Map<String, dynamic> row = {};
  if (observe['body'] is List && (observe['body'] as List).isNotEmpty) {
    row = Map<String, dynamic>.from((observe['body'] as List).first as Map);
  }
  add(
    'P3_money_not_persisted',
    '${row['status']}' != 'pago' && row['amount_paid_cents'] == null,
    row,
  );

  // ---- P3 email: buyer null; seller with products OK ----
  final enumB = await req(
    'POST',
    '$url/rest/v1/rpc/batata_find_user_id_by_email',
    BH,
    {'p_email': envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL')},
  );
  add('P3_email_buyer_null', enumB['body'] == null, {
    'body': enumB['body'],
  });
  final enumS = await req(
    'POST',
    '$url/rest/v1/rpc/batata_find_user_id_by_email',
    SH,
    {'p_email': envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL')},
  );
  add(
    'P3_email_seller_with_store',
    enumS['body'] == buyerId || enumS['http'] == 200,
    {'body': enumS['body'], 'http': enumS['http']},
  );

  // ---- P2 parallel checkout: same session id ----
  if (oid != null) {
    final f1 = req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      BH,
      {
        'order_id': oid,
        'buyer_id': buyerId,
        'shipping_method': 'mao',
      },
    );
    final f2 = req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      BH,
      {
        'order_id': oid,
        'buyer_id': buyerId,
        'shipping_method': 'mao',
      },
    );
    final pair = await Future.wait([f1, f2]);
    String? s1;
    String? s2;
    for (final p in pair) {
      if (p['body'] is Map) {
        final id = '${(p['body'] as Map)['checkoutSessionId'] ?? ''}';
        if (s1 == null) {
          s1 = id;
        } else {
          s2 = id;
        }
      }
    }
    final same = s1 != null && s1!.isNotEmpty && s1 == s2;
    add('P2_parallel_checkout_one_session', same, {
      's1': s1,
      's2': s2,
      'http': [pair[0]['http'], pair[1]['http']],
      'reused': [
        pair[0]['body'] is Map ? (pair[0]['body'] as Map)['reused_session'] : null,
        pair[1]['body'] is Map ? (pair[1]['body'] as Map)['reused_session'] : null,
      ],
    });
  }

  if (oid != null) {
    await req('DELETE', '$url/rest/v1/orders?id=eq.$oid', SVC);
  }
  if (pid != null) {
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
  }

  final failed = results.where((r) => r['ok'] != true).length;
  final outPath = 'tool/reports/sec_indep_1605_1606_hostile_$stamp.json';
  await File(outPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'stamp': stamp,
      'pass': results.length - failed,
      'fail': failed,
      'total': results.length,
      'results': results,
    }),
  );
  stdout.writeln('Wrote $outPath (${results.length - failed}/${results.length})');
  exit(failed == 0 ? 0 : 1);
}
