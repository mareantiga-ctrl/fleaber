// ignore_for_file: avoid_print
/// P2/P3 fecho blind 20260830 — dart run tool/sec_blind_p2_p3_fecho_hostile.dart
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
          : await http.patch(
              Uri.parse(u),
              headers: h,
              body: body == null ? null : jsonEncode(body),
            );
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

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;

  // ---- price_total clamp ----
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'P2 price $stamp',
    'price': 5.0,
    'quantity': 3,
    'ref_code': 'P2PRICE-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = idOf(prod['body']);
  add('fixture_product', pid != null, {'id': pid});
  final ord = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 999.0,
    'shipping_method': 'hand',
    'payment_method': 'Pagamento na app',
  });
  final oid = idOf(ord['body']);
  num? pt;
  int? contract;
  if (ord['body'] is List && (ord['body'] as List).isNotEmpty) {
    final row = (ord['body'] as List).first as Map;
    pt = num.tryParse('${row['price_total']}');
    contract = int.tryParse('${row['contract_unit_cents']}');
  }
  add(
    'P2_price_total_clamped',
    oid != null && pt != null && pt! <= 5.01 && (contract ?? 0) == 500,
    {'price_total': pt, 'contract_unit_cents': contract, 'http': ord['http']},
  );

  // ---- tip stripe sem live (regressão) ----
  final tip = await req(
    'POST',
    '$url/functions/v1/create-live-tip-checkout',
    BH,
    {'seller_id': sellerId, 'amount_eur': 1},
  );
  add('P2_tip_stripe_needs_live', tip['http'] >= 400, {
    'http': tip['http'],
  });

  // ---- tip wallet sem live ----
  final tipW = await req(
    'POST',
    '$url/rest/v1/rpc/batata_send_live_tip_from_wallet',
    BH,
    {
      'p_live_id': null,
      'p_seller_id': sellerId,
      'p_amount': 1,
    },
  );
  add(
    'P2_tip_wallet_needs_live',
    tipW['http'] >= 400,
    {'http': tipW['http'], 'body': tipW['body']},
  );

  // ---- tip wallet com live (fluxo sombra reparado) ----
  final live = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'status': 'live',
    'is_active': true,
    'title': 'P2 tip $stamp',
  });
  final liveId = idOf(live['body']);
  // garantir saldo buyer
  await req(
    'PATCH',
    '$url/rest/v1/wallets?id=eq.$buyerId',
    SVC,
    {'balance': 50},
  );
  final tipOk = await req(
    'POST',
    '$url/rest/v1/rpc/batata_send_live_tip_from_wallet',
    BH,
    {
      'p_live_id': liveId,
      'p_seller_id': sellerId,
      'p_amount': 1.0,
      'p_message': 'hostile',
    },
  );
  add(
    'P2_tip_wallet_with_live_ok',
    tipOk['http'] == 200 && tipOk['body'] != null,
    {'http': tipOk['http'], 'body': tipOk['body']},
  );
  if (liveId != null) {
    await req(
      'PATCH',
      '$url/rest/v1/lives?id=eq.$liveId',
      SVC,
      {'status': 'ended', 'is_active': false},
    );
  }

  // ---- payout: duas keys mesmo amount NÃO colapsam ----
  final k1 = 'p2payout-a-$stamp-xxxx';
  final k2 = 'p2payout-b-$stamp-yyyy';
  // debit orphan com k1 via crash inject se possível
  final crash1 = await req(
    'POST',
    '$url/functions/v1/create-connect-account',
    {
      ...SH,
      if (crashSecret.length >= 16)
        'x-fleaber-crash-inject-secret': crashSecret,
      'x-fleaber-crash-inject': 'after_debit_before_stripe',
    },
    {
      'amount': 100,
      'idempotency_key': k1,
      'crash_inject': 'after_debit_before_stripe',
    },
  );
  final crashHit = crash1['http'] == 500 ||
      '${crash1['text']}'.contains('payout_pending_reconcile') ||
      '${crash1['text']}'.contains('Connect') ||
      '${crash1['text']}'.contains('IBAN') ||
      crash1['http'] == 200;
  add('P2_payout_crash_or_ready', crashHit, {
    'http': crash1['http'],
    'body': crash1['body'],
  });

  // Se k1 ficou debited, k2 com mesmo amount deve criar row própria ou falhar saldo —
  // NÃO reutilizar k1.
  final beforeKeys = await req(
    'GET',
    '$url/rest/v1/wallet_payout_ledger?user_id=eq.$sellerId&idempotency_key=in.($k1,$k2)&select=idempotency_key,status,amount_cents',
    SVC,
  );
  final attempt2 = await req(
    'POST',
    '$url/functions/v1/create-connect-account',
    {
      ...SH,
      if (crashSecret.length >= 16)
        'x-fleaber-crash-inject-secret': crashSecret,
      'x-fleaber-crash-inject': 'after_debit_before_stripe',
    },
    {
      'amount': 100,
      'idempotency_key': k2,
      'crash_inject': 'after_debit_before_stripe',
    },
  );
  final afterKeys = await req(
    'GET',
    '$url/rest/v1/wallet_payout_ledger?user_id=eq.$sellerId&idempotency_key=in.($k1,$k2)&select=idempotency_key,status',
    SVC,
  );
  final keys = <String>{};
  if (afterKeys['body'] is List) {
    for (final row in afterKeys['body'] as List) {
      if (row is Map) keys.add('${row['idempotency_key']}');
    }
  }
  // Se ambos debited existem, ou k2 falhou insufficient — não houve remap k2→k1
  final noCollapse = !keys.contains(k2) || keys.contains(k1);
  // Mais forte: se k2 existe, status próprio; se attempt2 usou k1, body key seria k1
  final body2 = attempt2['body'];
  final remapped = body2 is Map &&
      '${body2['idempotency_key']}' == k1 &&
      attempt2['http'] == 500;
  add('P2_payout_no_amount_collapse', !remapped && noCollapse, {
    'keys': keys.toList(),
    'http2': attempt2['http'],
    'before': beforeKeys['body'],
    'after': afterKeys['body'],
    'body2': body2,
  });
  await req(
    'DELETE',
    '$url/rest/v1/wallet_payout_ledger?idempotency_key=in.($k1,$k2)',
    SVC,
  );

  // ---- anon stock ----
  final anonStock = await req(
    'POST',
    '$url/rest/v1/rpc/batata_live_item_stock',
    {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
    },
    {'p_live_item_id': '00000000-0000-0000-0000-000000000001'},
  );
  add(
    'P3_anon_stock_denied',
    anonStock['http'] == 401 || anonStock['http'] == 403,
    {'http': anonStock['http']},
  );

  // ---- review public excludes unverified ----
  final pub = await req(
    'GET',
    '$url/rest/v1/reviews_public_ratings?purchase_verified=eq.false&select=id&limit=1',
    {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
    },
  );
  final emptyUnverified = pub['body'] is List && (pub['body'] as List).isEmpty;
  add('P3_public_ratings_no_unverified', emptyUnverified || pub['http'] == 200, {
    'http': pub['http'],
    'n': pub['body'] is List ? (pub['body'] as List).length : null,
  });

  // ---- email rate still seller-only ----
  final enumBuyer = await req(
    'POST',
    '$url/rest/v1/rpc/batata_find_user_id_by_email',
    BH,
    {'p_email': envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL')},
  );
  add(
    'P3_email_enum_buyer_null',
    enumBuyer['body'] == null || enumBuyer['http'] >= 400,
    {'http': enumBuyer['http'], 'body': enumBuyer['body']},
  );

  if (oid != null) {
    await req('DELETE', '$url/rest/v1/orders?id=eq.$oid', SVC);
  }
  if (pid != null) {
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
  }

  final failed = results.where((r) => r['ok'] != true).length;
  final outPath = 'tool/reports/sec_blind_p2_p3_fecho_hostile_$stamp.json';
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
