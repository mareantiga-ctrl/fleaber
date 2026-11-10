// ignore_for_file: avoid_print
/// E2E Stripe Test — product swap hostil não cria cobrança barata.
/// dart run tool/sec_p001_e2e_stripe_hostile.dart
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final token = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );

  final expensive = await sb.insert('products', {
    'seller_id': sellerId,
    'title': 'P001 E2E expensive ${DateTime.now().microsecondsSinceEpoch}',
    'price': 80,
    'quantity': 2,
    'ref_code': 'P001E2E-${DateTime.now().microsecondsSinceEpoch}',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final cheap = await sb.insert('products', {
    'seller_id': sellerId,
    'title': 'P001 E2E cheap ${DateTime.now().microsecondsSinceEpoch}',
    'price': 0.5,
    'quantity': 5,
    'ref_code': 'P001E2Ec-${DateTime.now().microsecondsSinceEpoch}',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final order = await sb.insert('orders', {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': expensive['id'],
    'price_total': 1,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
  });

  final swap = await sb.invokeEdge(
    'create-payment-intent',
    {
      'amount': 50,
      'currency': 'eur',
      'product_id': cheap['id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'order_id': order['id'],
      'quantity': 1,
      'shipping': 350,
      'shipping_method': 'transportadora',
    },
    accessToken: token,
  );
  Map<String, dynamic> swapBody = {};
  try {
    swapBody = Map<String, dynamic>.from(jsonDecode(swap.body) as Map);
  } catch (_) {
    swapBody = {'raw': swap.body};
  }

  final legit = await sb.invokeEdge(
    'create-payment-intent',
    {
      'amount': 50,
      'currency': 'eur',
      'product_id': expensive['id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'order_id': order['id'],
      'quantity': 1,
      'shipping': 350,
      'shipping_method': 'transportadora',
    },
    accessToken: token,
  );
  Map<String, dynamic> legitBody = {};
  try {
    legitBody = Map<String, dynamic>.from(jsonDecode(legit.body) as Map);
  } catch (_) {
    legitBody = {'raw': legit.body};
  }

  final expected = 8833; // 80€ + 3.50 + prot
  final swapBlocked = swap.statusCode >= 400 &&
      (swapBody['error']?.toString().contains('product') ?? false);
  final legitOk = legit.statusCode == 200 &&
      legitBody['server_amount_cents'] == expected &&
      legitBody['amount_total'] == expected &&
      (legitBody['checkoutSessionId']?.toString().startsWith('cs_test_') ??
          false);

  // Prize forged E2E
  final prize = await sb.invokeEdge(
    'create-payment-intent',
    {
      'amount': 433,
      'currency': 'eur',
      'product_id': expensive['id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'order_id': order['id'],
      'quantity': 1,
      'shipping': 350,
      'shipping_method': 'transportadora',
      'prize_shipping': true,
    },
    accessToken: token,
  );
  Map<String, dynamic> prizeBody = {};
  try {
    prizeBody = Map<String, dynamic>.from(jsonDecode(prize.body) as Map);
  } catch (_) {
    prizeBody = {'raw': prize.body};
  }
  final prizeBlocked = prize.statusCode >= 400;

  final out = {
    'at': DateTime.now().toUtc().toIso8601String(),
    'checks': {
      'product_swap_rejected': swapBlocked,
      'legit_stripe_session_full_price': legitOk,
      'prize_forged_rejected': prizeBlocked,
    },
    'swap_http': swap.statusCode,
    'swap_error': swapBody['error'],
    'legit_http': legit.statusCode,
    'legit_server_amount_cents': legitBody['server_amount_cents'],
    'legit_amount_total': legitBody['amount_total'],
    'legit_session': legitBody['checkoutSessionId'],
    'prize_http': prize.statusCode,
    'prize_error': prizeBody['error'],
    'expected_cents': expected,
  };
  final ok = swapBlocked && legitOk && prizeBlocked;
  out['ok'] = ok;

  await Directory('tool/reports').create(recursive: true);
  await File('tool/reports/HARDENING_P0_01_E2E_STRIPE_HOSTILE.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(ok ? 'PASS E2E Stripe hostile' : 'FAIL E2E Stripe hostile');
  print(const JsonEncoder.withIndent('  ').convert(out));

  try {
    await sb.deleteWhere('chats', 'product_id=eq.${expensive['id']}');
  } catch (_) {}
  try {
    await sb.deleteWhere('orders', 'id=eq.${order['id']}');
  } catch (_) {}
  try {
    await sb.deleteWhere('products', 'id=eq.${expensive['id']}');
  } catch (_) {}
  try {
    await sb.deleteWhere('products', 'id=eq.${cheap['id']}');
  } catch (_) {}

  exit(ok ? 0 : 1);
}
