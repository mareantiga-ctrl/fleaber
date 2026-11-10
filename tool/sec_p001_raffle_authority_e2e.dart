// ignore_for_file: avoid_print
/// E2E Stripe Test — status/payment_method forjados não criam Session barata.
/// dart run tool/sec_p001_raffle_authority_e2e.dart
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

  final product = await sb.insert('products', {
    'seller_id': sellerId,
    'title': 'P001R E2E 80e ${DateTime.now().microsecondsSinceEpoch}',
    'price': 80,
    'quantity': 3,
    'ref_code': 'P001RE2E-${DateTime.now().microsecondsSinceEpoch}',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });

  Future<Map<String, dynamic>> tryHostile({
    required String label,
    required Map<String, dynamic> orderRow,
    bool prizeShipping = true,
  }) async {
    Map<String, dynamic> order;
    try {
      order = await sb.insertAsUser('orders', orderRow, accessToken: token);
    } catch (e) {
      return {'label': label, 'pass': true, 'detail': 'insert blocked: $e'};
    }
    // Se o trigger scrubou status, ainda tentar checkout hostil.
    final r = await sb.invokeEdge(
      'create-payment-intent',
      {
        'amount': 433,
        'currency': 'eur',
        'product_id': product['id'],
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': order['id'],
        'quantity': 1,
        'shipping': 350,
        'shipping_method': 'transportadora',
        if (prizeShipping) 'prize_shipping': true,
      },
      accessToken: token,
    );
    Map<String, dynamic> body = {};
    try {
      body = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    } catch (_) {
      body = {'raw': r.body};
    }
    final server = body['server_amount_cents'];
    final cheap = r.statusCode == 200 &&
        server is num &&
        server < 2000;
    final pass = !cheap;
    try {
      await sb.deleteWhere('orders', 'id=eq.${order['id']}');
    } catch (_) {}
    return {
      'label': label,
      'pass': pass,
      'http': r.statusCode,
      'server_amount_cents': server,
      'stored_status': order['status'],
      'stored_pm': order['payment_method'],
      'error': body['error'],
      'checkoutSessionId': body['checkoutSessionId'],
    };
  }

  final cases = <Map<String, dynamic>>[];
  cases.add(await tryHostile(
    label: 'INSERT_status_premio_rifa',
    orderRow: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': product['id'],
      'price_total': 80,
      'quantity': 1,
      'status': 'premio_rifa',
      'payment_method': 'Pagamento na app',
    },
  ));
  cases.add(await tryHostile(
    label: 'INSERT_payment_method_premio',
    orderRow: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': product['id'],
      'price_total': 80,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Prémio da Rifa',
    },
  ));

  // PATCH path
  final base = await sb.insertAsUser(
    'orders',
    {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': product['id'],
      'price_total': 80,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    },
    accessToken: token,
  );
  await sb.patchAsUser(
    'orders',
    'id=eq.${base['id']}',
    {'status': 'premio_rifa', 'payment_method': 'Prémio da Rifa'},
    accessToken: token,
  );
  final after = await sb.select('orders', filter: 'id=eq.${base['id']}', limit: 1);
  final r = await sb.invokeEdge(
    'create-payment-intent',
    {
      'amount': 433,
      'currency': 'eur',
      'product_id': product['id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'order_id': base['id'],
      'quantity': 1,
      'shipping': 350,
      'shipping_method': 'transportadora',
      'prize_shipping': true,
    },
    accessToken: token,
  );
  Map<String, dynamic> body = {};
  try {
    body = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
  } catch (_) {
    body = {'raw': r.body};
  }
  final server = body['server_amount_cents'];
  final cheap = r.statusCode == 200 && server is num && server < 2000;
  cases.add({
    'label': 'PATCH_status_and_pm',
    'pass': !cheap,
    'http': r.statusCode,
    'server_amount_cents': server,
    'stored_status': after.first['status'],
    'stored_pm': after.first['payment_method'],
    'error': body['error'],
    'checkoutSessionId': body['checkoutSessionId'],
  });
  try {
    await sb.deleteWhere('orders', 'id=eq.${base['id']}');
    await sb.deleteWhere('products', 'id=eq.${product['id']}');
  } catch (_) {}

  final failed = cases.where((c) => c['pass'] != true).length;
  for (final c in cases) {
    print('${c['pass'] == true ? "PASS" : "FAIL"} ${c['label']} — $c');
  }
  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'failed': failed,
    'cases': cases,
  };
  await Directory('tool/reports').create(recursive: true);
  await File('tool/reports/HARDENING_P0_01_RAFFLE_AUTHORITY_E2E.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('E2E failed=$failed/${cases.length}');
  exit(failed == 0 ? 0 : 1);
}
