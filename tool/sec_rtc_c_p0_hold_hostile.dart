// ignore_for_file: avoid_print
/// RTC-C-P0 double restitution + F-CAP-01 pending hold.
/// dart run tool/sec_rtc_c_p0_hold_hostile.dart
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

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final cleanup = <Future Function()>[];

  // ---- F-CAP-01: stock=1 → 2º INSERT reserva_pendente deve falhar ----
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'RTC hold $stamp',
    'price': 8.0,
    'quantity': 1,
    'ref_code': 'RTCHOLD-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = idOf(prod['body']);
  add('fixture_stock1', pid != null, {'id': pid});
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
    'price_total': 8.0,
    'shipping_method': 'hand',
  });
  final oid1 = idOf(o1['body']);
  add('CAP_first_pending_ok', oid1 != null && (o1['http'] as int) < 300, {
    'http': o1['http'],
    'id': oid1,
  });

  final o2 = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 8.0,
    'shipping_method': 'hand',
  });
  final oid2 = idOf(o2['body']);
  final blocked = (o2['http'] as int) >= 400 && oid2 == null;
  add('CAP_second_pending_blocked', blocked, {
    'http': o2['http'],
    'body': '${o2['text']}'.length > 180
        ? '${o2['text']}'.substring(0, 180)
        : o2['text'],
  });

  final held = await req(
    'POST',
    '$url/rest/v1/rpc/batata_product_held_qty',
    SVC,
    {'p_product_id': pid},
  );
  add('CAP_held_qty_ge_1', held['body'] == 1 || held['body'] == 1.0, {
    'held': held['body'],
  });

  // ---- RTC-C-P0: paid → dispute 100% wallet → refund-order must NOT Stripe full ----
  final paid = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'probe': 'setup_paid_order',
      'initial_qty': 2,
    },
  );
  Map<String, dynamic> paidBody = {};
  if (paid['body'] is Map) {
    paidBody = Map<String, dynamic>.from(paid['body'] as Map);
  }
  final paidOid = '${paidBody['order_id'] ?? ''}';
  final paidPid = '${paidBody['product_id'] ?? ''}';
  add(
    'P0_fixture_paid',
    paid['http'] == 200 && paidBody['ok'] == true && paidOid.isNotEmpty,
    {'order_id': paidOid, 'http': paid['http']},
  );
  if (paidPid.isNotEmpty) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/order_disputes?order_id=eq.$paidOid', SVC);
      await req('DELETE', '$url/rest/v1/orders?id=eq.$paidOid', SVC);
      await req('DELETE', '$url/rest/v1/products?id=eq.$paidPid', SVC);
    });
  }

  // seller: pago → enviado → entregue
  for (final st in ['enviado', 'entregue']) {
    await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$paidOid',
      SH,
      {'status': st},
    );
  }

  // dispute + seller offer 100%
  final disp = await req('POST', '$url/rest/v1/order_disputes', BH, {
    'order_id': paidOid,
    'buyer_id': buyerId,
    'reason': 'outro',
    'description': 'RTC hostile P0',
  });
  final did = idOf(disp['body']);
  if (did != null) {
    await req(
      'PATCH',
      '$url/rest/v1/order_disputes?id=eq.$did',
      SH,
      {
        'seller_offer_type': 'partial_refund',
        'seller_refund_percent': 100,
      },
    );
  }
  add('P0_dispute_offer', did != null, {'dispute_id': did});

  final balBefore = await req(
    'GET',
    '$url/rest/v1/wallets?select=balance&id=eq.$buyerId',
    SVC,
  );
  final beforeBal = balBefore['body'] is List && (balBefore['body'] as List).isNotEmpty
      ? double.tryParse('${(balBefore['body'] as List).first['balance']}') ?? 0
      : 0.0;

  final part = await req(
    'POST',
    '$url/rest/v1/rpc/batata_process_partial_refund_dispute',
    BH,
    {'p_order_id': paidOid, 'p_refund_percent': 100},
  );
  final balAfterWallet = await req(
    'GET',
    '$url/rest/v1/wallets?select=balance&id=eq.$buyerId',
    SVC,
  );
  final afterWalletBal =
      balAfterWallet['body'] is List && (balAfterWallet['body'] as List).isNotEmpty
          ? double.tryParse('${(balAfterWallet['body'] as List).first['balance']}') ??
              0
          : 0.0;
  final walletMinted = afterWalletBal - beforeBal;
  add(
    'P0_wallet_partial_ok',
    part['body'] == true && walletMinted >= 5.0,
    {'rpc': part['body'], 'delta': walletMinted},
  );

  final refund = await req(
    'POST',
    '$url/functions/v1/refund-order',
    SH,
    {'order_id': paidOid},
  );
  final refundBody = refund['body'] is Map
      ? Map<String, dynamic>.from(refund['body'] as Map)
      : <String, dynamic>{};
  final blockedStripe = (refund['http'] as int) == 422 &&
      (refundBody['code'] == 'wallet_refund_already_processed' ||
          refundBody['reason'] == 'wallet_refund_covers_capture');

  final ordAfter = await req(
    'GET',
    '$url/rest/v1/orders?select=status,stripe_refund_id&id=eq.$paidOid',
    SVC,
  );
  final oRow = ordAfter['body'] is List && (ordAfter['body'] as List).isNotEmpty
      ? (ordAfter['body'] as List).first as Map
      : {};
  final noStripeRefund = '${oRow['stripe_refund_id'] ?? ''}'.trim().isEmpty;
  final stillNotCancelFromStripe = '${oRow['status']}'.toLowerCase() != 'cancelado' ||
      noStripeRefund;

  add('P0_refund_order_blocked', blockedStripe && noStripeRefund, {
    'http': refund['http'],
    'code': refundBody['code'],
    'stripe_refund_id': oRow['stripe_refund_id'],
    'status': oRow['status'],
    'still_ok': stillNotCancelFromStripe,
  });

  // wallet must keep credit (no clawback required for this assert); Stripe must not add second path
  final balFinal = await req(
    'GET',
    '$url/rest/v1/wallets?select=balance&id=eq.$buyerId',
    SVC,
  );
  final finalBal = balFinal['body'] is List && (balFinal['body'] as List).isNotEmpty
      ? double.tryParse('${(balFinal['body'] as List).first['balance']}') ?? 0
      : 0.0;
  add(
    'P0_no_double_path',
    blockedStripe && (finalBal - beforeBal) >= 5.0 && noStripeRefund,
    {'wallet_delta': finalBal - beforeBal, 'stripe_refund': oRow['stripe_refund_id']},
  );

  for (final f in cleanup.reversed) {
    try {
      await f();
    } catch (_) {}
  }

  final pass = results.where((r) => r['ok'] == true).length;
  final fail = results.where((r) => r['ok'] != true).length;
  final outPath = 'tool/reports/sec_rtc_c_p0_hold_hostile_$stamp.json';
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
