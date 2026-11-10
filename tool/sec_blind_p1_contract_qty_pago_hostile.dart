// ignore_for_file: avoid_print
/// Blind P1-01 / P1-03 / P1-04 hostile battery (pré-Fase 4).
/// dart run tool/sec_blind_p1_contract_qty_pago_hostile.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> postJson(
  String url,
  Map<String, String> h,
  Object body,
) async {
  final r = await http.post(
    Uri.parse(url),
    headers: h,
    body: jsonEncode(body),
  );
  dynamic p;
  try {
    p = jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p};
}

num n(Object? v) => v is num ? v : num.tryParse('$v') ?? -1;

void main() async {
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
  void add(String id, bool ok, Object detail) {
    results.add({'id': id, 'ok': ok, 'detail': detail});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $detail');
  }

  Future<void> cleanup(String? productId) async {
    if (productId == null) return;
    await http.delete(
      Uri.parse('$url/rest/v1/orders?product_id=eq.$productId'),
      headers: SVC,
    );
    try {
      await http.delete(
        Uri.parse('$url/rest/v1/chats?product_id=eq.$productId'),
        headers: SVC,
      );
    } catch (_) {}
    await http.delete(
      Uri.parse('$url/rest/v1/products?id=eq.$productId'),
      headers: SVC,
    );
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;

  // ========== P1-01 PRICE-1 catalog hike ==========
  final p1 = await sb.insert('products', {
    'seller_id': sellerId,
    'title': 'BLIND P101 $stamp',
    'price': 12.0,
    'quantity': 5,
    'list_on_marketplace': false,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final o1 = await http.post(
    Uri.parse('$url/rest/v1/orders'),
    headers: BH,
    body: jsonEncode({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': p1['id'],
      'quantity': 1,
      'price_total': 12.0,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    }),
  );
  stdout.writeln('o1 insert ${o1.statusCode} ${o1.body}');
  final o1decoded = jsonDecode(o1.body);
  if (o1decoded is! List || o1decoded.isEmpty) {
    add('P101_CONTRACT_SEALED_AT_INSERT', false, {
      'http': o1.statusCode,
      'body': o1.body,
    });
    await cleanup(p1['id']?.toString());
    final path = 'tool/reports/HARDENING_POS_NOVA_AUDITORIA_CEGA_HOSTILE.json';
    await File(path).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'ok': false,
        'results': results,
      }),
    );
    exit(1);
  }
  final o1row = o1decoded.first as Map;
  final oid1 = o1row['id'] as String;
  final contractUnit = n(o1row['contract_unit_cents']);
  add('P101_CONTRACT_SEALED_AT_INSERT', contractUnit == 1200, {
    'contract_unit_cents': contractUnit,
    'http': o1.statusCode,
  });

  await http.patch(
    Uri.parse('$url/rest/v1/products?id=eq.${p1['id']}'),
    headers: SH,
    body: jsonEncode({'price': 80.0}),
  );

  final cpi1 = await postJson(
    '$url/functions/v1/create-payment-intent',
    BH,
    {
      'buyer_id': buyerId,
      'order_id': oid1,
      'shipping_method': 'entrega em mão',
      'amount': 50, // underpay attempt
    },
  );
  // 12€ + prot 0.65+5%*12 = 0.65+0.6=1.25 → 1325 cents hand
  final amt1 = cpi1['body'] is Map
      ? n((cpi1['body'] as Map)['server_amount_cents'])
      : -1;
  final expectHand12 = 1200 +
      (0.65 + 12 * 0.05).let((x) => (x * 100).round()); // 1200+125=1325
  // Use exact: protectionFeeCents(1200,0) = round((0.65+6)*100)? baseEur=12, fee=0.65+0.6=1.25 → 125
  add(
    'P101_PRICE1_HIKE_QUOTE_USES_CONTRACT',
    cpi1['http'] == 200 && amt1 == 1325,
    {'http': cpi1['http'], 'amt': amt1, 'expect': 1325, 'err': cpi1['body']},
  );
  add(
    'P101_PRICE2_UNDERPAY_IGNORED',
    cpi1['http'] == 200 && amt1 == 1325,
    {'amt': amt1},
  );

  // ========== P1-03 QTY ==========
  final patchQty = await http.patch(
    Uri.parse('$url/rest/v1/orders?id=eq.$oid1'),
    headers: BH,
    body: jsonEncode({'quantity': 4}),
  );
  final qtyLive = await http.get(
    Uri.parse('$url/rest/v1/orders?id=eq.$oid1&select=quantity,contract_qty'),
    headers: BH,
  );
  final qtyRow = (jsonDecode(qtyLive.body) as List).first as Map;
  add(
    'P103_QTY1_BUYER_PATCH_BLOCKED',
    n(qtyRow['quantity']) == 1 && n(qtyRow['contract_qty']) == 1,
    {'http': patchQty.statusCode, 'row': qtyRow},
  );

  final patchBad = await http.patch(
    Uri.parse('$url/rest/v1/orders?id=eq.$oid1'),
    headers: BH,
    body: jsonEncode({'quantity': 0}),
  );
  final qty2 = await http.get(
    Uri.parse('$url/rest/v1/orders?id=eq.$oid1&select=quantity'),
    headers: BH,
  );
  add(
    'P103_QTY2_ZERO_STAYS_ONE',
    n((jsonDecode(qty2.body) as List).first['quantity']) == 1,
    {'http': patchBad.statusCode},
  );

  // INSERT qty > stock → reject
  final insOver = await http.post(
    Uri.parse('$url/rest/v1/orders'),
    headers: BH,
    body: jsonEncode({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': p1['id'],
      'quantity': 99,
      'price_total': 12.0,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    }),
  );
  add(
    'P103_INSERT_QTY_EXCEEDS_STOCK_REJECT',
    insOver.statusCode >= 400,
    {'http': insOver.statusCode, 'body': insOver.body.length > 120 ? '${insOver.body.substring(0, 120)}…' : insOver.body},
  );

  // ========== P1-04 PAY ==========
  final pPay = await sb.insert('products', {
    'seller_id': sellerId,
    'title': 'BLIND P104 $stamp',
    'price': 5.0,
    'quantity': 3,
    'list_on_marketplace': false,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final oStripe = await http.post(
    Uri.parse('$url/rest/v1/orders'),
    headers: BH,
    body: jsonEncode({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pPay['id'],
      'quantity': 1,
      'price_total': 5.0,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    }),
  );
  final oidS = (jsonDecode(oStripe.body) as List).first['id'] as String;

  final sellerPago = await http.patch(
    Uri.parse('$url/rest/v1/orders?id=eq.$oidS'),
    headers: SH,
    body: jsonEncode({'status': 'pago'}),
  );
  final stS = await http.get(
    Uri.parse(
      '$url/rest/v1/orders?id=eq.$oidS&select=status,amount_paid_cents,stock_units_applied',
    ),
    headers: SVC,
  );
  final stSrow = (jsonDecode(stS.body) as List).first as Map;
  add(
    'P104_PAY1_SELLER_STRIPE_PAGO_BLOCKED',
    '${stSrow['status']}' == 'reserva_pendente' &&
        stSrow['amount_paid_cents'] == null,
    {'http': sellerPago.statusCode, 'row': stSrow},
  );

  // payment_method switch attempt
  final switchPm = await http.patch(
    Uri.parse('$url/rest/v1/orders?id=eq.$oidS'),
    headers: SH,
    body: jsonEncode({'payment_method': 'MB WAY', 'status': 'pago'}),
  );
  final stS2 = await http.get(
    Uri.parse('$url/rest/v1/orders?id=eq.$oidS&select=status,payment_method'),
    headers: SVC,
  );
  final stS2row = (jsonDecode(stS2.body) as List).first as Map;
  add(
    'P104_PAY7_CANNOT_SWITCH_TO_MBWAY',
    '${stS2row['payment_method']}'.contains('app') &&
        '${stS2row['status']}' == 'reserva_pendente',
    {'http': switchPm.statusCode, 'row': stS2row},
  );

  // MB WAY seller pago OK
  final oMb = await http.post(
    Uri.parse('$url/rest/v1/orders'),
    headers: BH,
    body: jsonEncode({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pPay['id'],
      'quantity': 1,
      'price_total': 5.0,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    }),
  );
  final oidMb = (jsonDecode(oMb.body) as List).first['id'] as String;
  final mbPago = await http.patch(
    Uri.parse('$url/rest/v1/orders?id=eq.$oidMb'),
    headers: SH,
    body: jsonEncode({'status': 'pago'}),
  );
  final mbLive = await http.get(
    Uri.parse(
      '$url/rest/v1/orders?id=eq.$oidMb&select=status,amount_paid_cents,stock_units_applied',
    ),
    headers: SVC,
  );
  final mbRow = (jsonDecode(mbLive.body) as List).first as Map;
  add(
    'P104_PAY4_MBWAY_SELLER_PAGO_OK',
    '${mbRow['status']}' == 'pago' && mbRow['amount_paid_cents'] == null,
    {'http': mbPago.statusCode, 'row': mbRow},
  );

  // Wallet no mint after MB WAY
  final wBefore = await http.get(
    Uri.parse('$url/rest/v1/wallets?id=eq.$sellerId&select=balance'),
    headers: SVC,
  );
  // already pago — release should be false
  final rel = await postJson(
    '$url/rest/v1/rpc/batata_release_seller_wallet_for_order',
    BH,
    {'p_order_id': oidMb},
  );
  final wAfter = await http.get(
    Uri.parse('$url/rest/v1/wallets?id=eq.$sellerId&select=balance'),
    headers: SVC,
  );
  final balB = n((jsonDecode(wBefore.body) as List).first['balance']);
  final balA = n((jsonDecode(wAfter.body) as List).first['balance']);
  add(
    'P104_PAY6_NO_WALLET_MINT',
    balA == balB && (rel['body'] == false || rel['http'] == 200),
    {'before': balB, 'after': balA, 'release': rel},
  );

  await cleanup(p1['id']?.toString());
  await cleanup(pPay['id']?.toString());

  final fail = results.where((r) => r['ok'] != true).length;
  final path = 'tool/reports/HARDENING_POS_NOVA_AUDITORIA_CEGA_HOSTILE.json';
  await File(path).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'test': 'blind_p1_contract_qty_pago',
      'at': DateTime.now().toUtc().toIso8601String(),
      'ok': fail == 0,
      'fail': fail,
      'results': results,
    }),
  );
  stdout.writeln('evidence -> $path ($fail fail)');
  exit(fail == 0 ? 0 : 1);
}

extension on double {
  T let<T>(T Function(double) f) => f(this);
}
