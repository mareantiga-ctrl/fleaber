// ignore_for_file: avoid_print
/// APP-214 reteste — valida fórmulas saco Stripe + opcional encomenda staging.
///
///   dart run tool/c27_app214_retest.dart
///   dart run tool/c27_app214_retest.dart --order-id=UUID
library;

import 'dart:convert';
import 'dart:io';

import 'package:fleaber/utils/fee_calculator.dart';

import 'live_ops_staging_client.dart';

void main(List<String> args) async {
  var orderId = '';
  for (final a in args) {
    if (a.startsWith('--order-id=')) orderId = a.split('=').last.trim();
  }

  const items = 11.0;
  const shipping = kFleaberCarrierShippingEur;
  final buyerTotal = liveBagBuyerTotalEur(
    itemsSubtotalEur: items,
    shippingEur: shipping,
  );
  final protection = calculateFleaberProtectionFee(items, shippingEur: shipping);
  final seller = liveSellerEarningsEur(
    storedPriceTotal: buyerTotal,
    isDirectPayment: false,
    lineItemEur: items,
    shippingEur: shipping,
  );

  final formula = {
    'items_eur': items,
    'shipping_eur': shipping,
    'protection_eur': protection,
    'buyer_total_eur': buyerTotal,
    'seller_ganhos_eur': seller,
    'stripe_cents_expected': (buyerTotal * 100).round(),
  };

  var pass = buyerTotal == 15.88 && seller == 14.5 && protection == 1.38;
  print(jsonEncode({'phase': 'formula', 'pass': pass, 'formula': formula}));

  if (!pass) exit(1);

  if (!isUuid(orderId)) {
    print(jsonEncode({
      'phase': 'staging',
      'skipped': true,
      'reason': 'no --order-id; formula PASS only',
    }));
    exit(0);
  }

  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final order =
      (await client.select('orders', filter: 'id=eq.$orderId', limit: 1)).first;
  final stored = (order['price_total'] as num?)?.toDouble() ?? 0;
  final events = await client.select(
    'stripe_checkout_events',
    filter: 'order_id=eq.$orderId&event=eq.checkout_session_created',
    limit: 3,
  );
  int? stripeCents;
  for (final e in events) {
    final detail = e['detail'];
    if (detail is Map && detail['amount'] != null) {
      stripeCents = (detail['amount'] as num).toInt();
      break;
    }
  }

  final wallet = await client.select(
    'wallet_transactions',
    filter: 'order_id=eq.$orderId&type=eq.compra',
    limit: 1,
  );
  final walletAmt = wallet.isEmpty
      ? null
      : (wallet.first['amount'] as num?)?.toDouble();

  final stagingPass = (stored - buyerTotal).abs() < 0.011 &&
      stripeCents == formula['stripe_cents_expected'] &&
      walletAmt != null &&
      (walletAmt + buyerTotal).abs() < 0.011;

  final out = {
    'phase': 'staging',
    'pass': stagingPass,
    'order_id': orderId,
    'price_total_bd': stored,
    'stripe_cents': stripeCents,
    'wallet_compra': walletAmt,
    'expected_buyer_total': buyerTotal,
  };
  final path = 'tool/reports/battery_c27_2026-08-23/bd/c27_app214_retest.json';
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
  exit(stagingPass ? 0 : 1);
}
