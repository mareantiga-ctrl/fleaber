// ignore_for_file: avoid_print
/// E2E C3/C4 — crash real entre Stripe refund e finalize DB.
/// dart run tool/sec_residuais_refund_crash_e2e.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> e2eProbe(
  String url,
  String svc,
  String e2eSecret,
  Map<String, dynamic> body,
) async {
  final res = await http.post(
    Uri.parse('$url/functions/v1/sec-fase2-e2e-oversell'),
    headers: {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
      'Content-Type': 'application/json',
      'x-fleaber-e2e-secret': e2eSecret,
    },
    body: jsonEncode(body),
  );
  Map<String, dynamic> parsed = {};
  try {
    final d = jsonDecode(res.body);
    if (d is Map) parsed = Map<String, dynamic>.from(d);
  } catch (_) {}
  parsed['_http'] = res.statusCode;
  return parsed;
}

Future<Map<String, dynamic>> refundOrder(
  String url,
  String anon,
  String sellerToken,
  String crashSecret, {
  required String orderId,
  String? crashInject,
}) async {
  final headers = <String, String>{
    'apikey': anon,
    'Authorization': 'Bearer $sellerToken',
    'Content-Type': 'application/json',
  };
  if (crashInject != null) {
    headers['x-fleaber-crash-inject-secret'] = crashSecret;
    headers['x-fleaber-crash-inject'] = crashInject;
  }
  final res = await http.post(
    Uri.parse('$url/functions/v1/refund-order'),
    headers: headers,
    body: jsonEncode({
      'order_id': orderId,
      if (crashInject != null) 'crash_inject': crashInject,
    }),
  );
  Map<String, dynamic> parsed = {};
  try {
    final d = jsonDecode(res.body);
    if (d is Map) parsed = Map<String, dynamic>.from(d);
  } catch (_) {
    parsed['raw'] = res.body;
  }
  parsed['_http'] = res.statusCode;
  return parsed;
}

Future<Map<String, dynamic>> readOrder(
  LiveOpsStagingClient sb,
  String orderId,
) async {
  final rows = await sb.select('orders', filter: 'id=eq.$orderId', limit: 1);
  return rows.isEmpty ? {} : rows.first;
}

Future<Map<String, dynamic>> readProduct(
  LiveOpsStagingClient sb,
  String productId,
) async {
  final rows = await sb.select('products', filter: 'id=eq.$productId', limit: 1);
  return rows.isEmpty ? {} : rows.first;
}

Future<double?> walletBal(LiveOpsStagingClient sb, String uid) async {
  final rows = await sb.select('wallets', filter: 'id=eq.$uid', limit: 1);
  if (rows.isEmpty) return null;
  return (rows.first['balance'] as num?)?.toDouble();
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final crashSecret = envRequire(env, 'FLEABER_STAGING_CRASH_INJECT_SECRET');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final sellerToken = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  final out = <String, dynamic>{
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'mode': 'stripe_test_staging',
  };

  // ========== C3 — after_stripe_before_db ==========
  print('=== C3 setup paid order ===');
  final setupC3 = await e2eProbe(url, svc, crashSecret, {
    'probe': 'setup_paid_order',
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'initial_qty': 2,
  });
  out['c3_setup'] = setupC3;

  final orderC3 = setupC3['order_id']?.toString() ?? '';
  final productC3 = setupC3['product_id']?.toString() ?? '';
  final piC3 = setupC3['payment_intent_id']?.toString() ?? '';
  final qtyInitialC3 = (setupC3['initial_qty'] as num?)?.toInt() ?? 2;
  final buyerW0 = await walletBal(sb, buyerId);
  final sellerW0 = await walletBal(sb, sellerId);

  final piPaid = setupC3['pi_status'] == 'succeeded' &&
      setupC3['ok'] == true &&
      (setupC3['order'] as Map?)?['status'] == 'pago' &&
      ((setupC3['order'] as Map?)?['stock_units_applied'] as num?)?.toInt() == 1;

  print('=== C3 crash inject after_stripe_before_db ===');
  final crashC3 = await refundOrder(
    url,
    anon,
    sellerToken,
    crashSecret,
    orderId: orderC3,
    crashInject: 'after_stripe_before_db',
  );
  out['c3_crash'] = crashC3;

  final orderAfterCrash = await readOrder(sb, orderC3);
  final stripeAfterCrash = await e2eProbe(url, svc, crashSecret, {
    'probe': 'list_stripe_refunds',
    'payment_intent_id': piC3,
  });
  out['c3_stripe_after_crash'] = stripeAfterCrash;

  final refundIdCrash = crashC3['refund_id']?.toString() ?? '';
  final stripeRefundCount1 =
      (stripeAfterCrash['refund_count'] as num?)?.toInt() ?? -1;
  final dbNotFinalized = orderAfterCrash['status'] != 'cancelado' &&
      (orderAfterCrash['stripe_refund_id'] == null ||
          '${orderAfterCrash['stripe_refund_id']}'.trim().isEmpty);

  print('=== C3 retry 1 (no crash) ===');
  await Future<void>.delayed(const Duration(milliseconds: 800));
  final retryC3a = await refundOrder(
    url,
    anon,
    sellerToken,
    crashSecret,
    orderId: orderC3,
  );
  out['c3_retry1'] = retryC3a;

  final orderAfterRetry1 = await readOrder(sb, orderC3);
  final productAfterRetry1 = await readProduct(sb, productC3);
  final stripeAfterRetry1 = await e2eProbe(url, svc, crashSecret, {
    'probe': 'list_stripe_refunds',
    'payment_intent_id': piC3,
  });
  out['c3_stripe_after_retry1'] = stripeAfterRetry1;

  final buyerW1 = await walletBal(sb, buyerId);
  final sellerW1 = await walletBal(sb, sellerId);

  print('=== C3 retry 2 (idempotency) ===');
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final retryC3b = await refundOrder(
    url,
    anon,
    sellerToken,
    crashSecret,
    orderId: orderC3,
  );
  out['c3_retry2'] = retryC3b;

  final orderAfterRetry2 = await readOrder(sb, orderC3);
  final productAfterRetry2 = await readProduct(sb, productC3);
  final stripeAfterRetry2 = await e2eProbe(url, svc, crashSecret, {
    'probe': 'list_stripe_refunds',
    'payment_intent_id': piC3,
  });
  out['c3_stripe_after_retry2'] = stripeAfterRetry2;

  final qtyFinalC3 = (productAfterRetry2['quantity'] as num?)?.toInt();
  final stripeRefundCountFinal =
      (stripeAfterRetry2['refund_count'] as num?)?.toInt() ?? -1;

  final c3Pass = piPaid &&
      crashC3['_http'] == 500 &&
      crashC3['needs_reconcile'] == true &&
      refundIdCrash.startsWith('re_') &&
      stripeRefundCount1 == 1 &&
      dbNotFinalized &&
      retryC3a['ok'] == true &&
      orderAfterRetry1['status'] == 'cancelado' &&
      '${orderAfterRetry1['stripe_refund_id']}'.startsWith('re_') &&
      stripeRefundCountFinal == 1 &&
      qtyFinalC3 == qtyInitialC3 &&
      (buyerW0 ?? 0) == (buyerW1 ?? 0) &&
      (sellerW0 ?? 0) == (sellerW1 ?? 0) &&
      (retryC3b['ok'] == true || retryC3b['already_refunded'] == true) &&
      orderAfterRetry2['status'] == 'cancelado' &&
      (productAfterRetry2['quantity'] as num?)?.toInt() == qtyInitialC3;

  out['c3'] = {
    'pass': c3Pass,
    'pi_paid': piPaid,
    'stripe_refund_created': stripeRefundCount1 == 1,
    'retry_second_refund': stripeRefundCountFinal > 1,
    'order_converged': orderAfterRetry1['status'] == 'cancelado',
    'stock_restored_once': qtyFinalC3 == qtyInitialC3,
    'wallet_coherent':
        (buyerW0 ?? 0) == (buyerW1 ?? 0) && (sellerW0 ?? 0) == (sellerW1 ?? 0),
  };

  await e2eProbe(url, svc, crashSecret, {
    'probe': 'cleanup_fixture',
    'product_id': productC3,
  });

  // ========== C4 — after_db_before_response ==========
  print('=== C4 setup paid order ===');
  final setupC4 = await e2eProbe(url, svc, crashSecret, {
    'probe': 'setup_paid_order',
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'initial_qty': 2,
  });
  out['c4_setup'] = setupC4;

  final orderC4 = setupC4['order_id']?.toString() ?? '';
  final productC4 = setupC4['product_id']?.toString() ?? '';
  final piC4 = setupC4['payment_intent_id']?.toString() ?? '';
  final qtyInitialC4 = (setupC4['initial_qty'] as num?)?.toInt() ?? 2;
  final buyerW4_0 = await walletBal(sb, buyerId);
  final sellerW4_0 = await walletBal(sb, sellerId);

  print('=== C4 crash inject after_db_before_response ===');
  final crashC4 = await refundOrder(
    url,
    anon,
    sellerToken,
    crashSecret,
    orderId: orderC4,
    crashInject: 'after_db_before_response',
  );
  out['c4_crash'] = crashC4;

  final orderAfterCrashC4 = await readOrder(sb, orderC4);
  final productAfterCrashC4 = await readProduct(sb, productC4);
  final stripeAfterCrashC4 = await e2eProbe(url, svc, crashSecret, {
    'probe': 'list_stripe_refunds',
    'payment_intent_id': piC4,
  });
  out['c4_stripe_after_crash'] = stripeAfterCrashC4;

  print('=== C4 retry (lost HTTP response) ===');
  await Future<void>.delayed(const Duration(milliseconds: 800));
  final retryC4 = await refundOrder(
    url,
    anon,
    sellerToken,
    crashSecret,
    orderId: orderC4,
  );
  out['c4_retry'] = retryC4;

  final orderAfterRetryC4 = await readOrder(sb, orderC4);
  final productAfterRetryC4 = await readProduct(sb, productC4);
  final stripeAfterRetryC4 = await e2eProbe(url, svc, crashSecret, {
    'probe': 'list_stripe_refunds',
    'payment_intent_id': piC4,
  });
  out['c4_stripe_after_retry'] = stripeAfterRetryC4;

  final buyerW4_1 = await walletBal(sb, buyerId);
  final sellerW4_1 = await walletBal(sb, sellerId);

  print('=== C4 retry 2 ===');
  final retryC4b = await refundOrder(
    url,
    anon,
    sellerToken,
    crashSecret,
    orderId: orderC4,
  );
  out['c4_retry2'] = retryC4b;

  final productAfterRetryC4b = await readProduct(sb, productC4);
  final stripeCountC4 =
      (stripeAfterRetryC4['refund_count'] as num?)?.toInt() ?? -1;

  final c4Pass = setupC4['ok'] == true &&
      crashC4['_http'] == 500 &&
      crashC4['needs_reconcile'] == true &&
      orderAfterCrashC4['status'] == 'cancelado' &&
      '${orderAfterCrashC4['stripe_refund_id']}'.startsWith('re_') &&
      (stripeAfterCrashC4['refund_count'] as num?) == 1 &&
      (productAfterCrashC4['quantity'] as num?)?.toInt() == qtyInitialC4 &&
      (retryC4['ok'] == true || retryC4['already_refunded'] == true) &&
      stripeCountC4 == 1 &&
      (productAfterRetryC4['quantity'] as num?)?.toInt() == qtyInitialC4 &&
      (buyerW4_0 ?? 0) == (buyerW4_1 ?? 0) &&
      (sellerW4_0 ?? 0) == (sellerW4_1 ?? 0) &&
      (retryC4b['ok'] == true || retryC4b['already_refunded'] == true) &&
      (productAfterRetryC4b['quantity'] as num?)?.toInt() == qtyInitialC4;

  out['c4'] = {
    'pass': c4Pass,
    'stripe_refund_created': (stripeAfterCrashC4['refund_count'] as num?) == 1,
    'retry_second_refund': stripeCountC4 > 1,
    'order_converged': orderAfterCrashC4['status'] == 'cancelado',
    'stock_restored_once':
        (productAfterRetryC4b['quantity'] as num?)?.toInt() == qtyInitialC4,
    'wallet_coherent': (buyerW4_0 ?? 0) == (buyerW4_1 ?? 0) &&
        (sellerW4_0 ?? 0) == (sellerW4_1 ?? 0),
    'retry_idempotent':
        retryC4['ok'] == true || retryC4['already_refunded'] == true,
  };

  await e2eProbe(url, svc, crashSecret, {
    'probe': 'cleanup_fixture',
    'product_id': productC4,
  });

  final e2eClosed = c3Pass && c4Pass;
  out['summary'] = {
    'c3_after_stripe_before_db': c3Pass ? 'PASS' : 'FAIL',
    'c4_after_db_before_response': c4Pass ? 'PASS' : 'FAIL',
    'refund_crash_retry_e2e': e2eClosed ? 'FECHADO' : 'PARCIAL',
  };

  final reportPath = 'tool/reports/HARDENING_RESIDUAIS_REFUND_CRASH_E2E.json';
  await File(reportPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(out),
  );

  print('\n--- RESULTADO ---');
  print('C3 after_stripe_before_db: ${c3Pass ? "PASS" : "FAIL"}');
  print(
    'Stripe refund real criado: ${stripeRefundCount1 == 1 ? "SIM" : "NÃO"}',
  );
  print(
    'retry criou segundo refund: ${stripeRefundCountFinal > 1 ? "SIM" : "NÃO"}',
  );
  print(
    'order convergiu: ${orderAfterRetry1['status'] == 'cancelado' ? "SIM" : "NÃO"}',
  );
  print(
    'stock restaurado exatamente 1x: ${qtyFinalC3 == qtyInitialC3 ? "SIM" : "NÃO"}',
  );
  print(
    'wallet coerente: ${(buyerW0 ?? 0) == (buyerW1 ?? 0) && (sellerW0 ?? 0) == (sellerW1 ?? 0) ? "SIM" : "NÃO"}',
  );
  print('C4 after_db_before_response: ${c4Pass ? "PASS" : "FAIL"}');
  print(
    'retry idempotente: ${retryC4['ok'] == true || retryC4['already_refunded'] == true ? "SIM" : "NÃO"}',
  );
  print('refund crash/retry E2E: ${e2eClosed ? "FECHADO" : "PARCIAL"}');
  print('Escrito: $reportPath');

  exit(e2eClosed ? 0 : 1);
}
