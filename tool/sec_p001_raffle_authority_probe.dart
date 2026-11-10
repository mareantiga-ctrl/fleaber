// ignore_for_file: avoid_print
/// Probe pré-fix: forjar premio_rifa / payment_method → quote barato?
/// dart run tool/sec_p001_raffle_authority_probe.dart
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: service,
  );

  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final buyerToken = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );

  final product = await sb.insert('products', {
    'seller_id': sellerId,
    'title': 'P001 raffle probe 80e ${DateTime.now().microsecondsSinceEpoch}',
    'price': 80.0,
    'quantity': 5,
    'ref_code': 'P001R-${DateTime.now().microsecondsSinceEpoch}',
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final productId = product['id'].toString();

  Future<Map<String, dynamic>> checkout(
    String orderId, {
    bool prize = true,
  }) async {
    final r = await sb.invokeEdge(
      'create-payment-intent',
      {
        'amount': prize ? 433 : 8833,
        'currency': 'eur',
        'product_id': productId,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': orderId,
        'quantity': 1,
        'shipping': 350,
        'shipping_method': 'transportadora',
        if (prize) 'prize_shipping': true,
      },
      accessToken: buyerToken,
    );
    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    } catch (_) {
      body = {'raw': r.body};
    }
    return {'status': r.statusCode, ...body};
  }

  // A) INSERT status=premio_rifa as buyer
  print('--- A INSERT status=premio_rifa ---');
  try {
    final o = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': productId,
        'price_total': 80.0,
        'quantity': 1,
        'status': 'premio_rifa',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
    print('INSERT ok id=${o['id']} status=${o['status']}');
    final c = await checkout(o['id'].toString());
    print('checkout: status=${c['status']} server=${c['server_amount_cents']} err=${c['error']}');
  } catch (e) {
    print('INSERT blocked: $e');
  }

  // B) INSERT payment_method prize
  print('--- B INSERT payment_method premio ---');
  try {
    final o = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': productId,
        'price_total': 80.0,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Prémio da Rifa',
      },
      accessToken: buyerToken,
    );
    print('INSERT ok id=${o['id']} pm=${o['payment_method']} status=${o['status']}');
    final c = await checkout(o['id'].toString());
    print('checkout: status=${c['status']} server=${c['server_amount_cents']} err=${c['error']}');
  } catch (e) {
    print('INSERT blocked: $e');
  }

  // C) PATCH status → premio_rifa
  print('--- C PATCH status → premio_rifa ---');
  try {
    final o = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': productId,
        'price_total': 80.0,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'premio_rifa'},
      accessToken: buyerToken,
    );
    final rows = await sb.select('orders', filter: 'id=eq.${o['id']}', limit: 1);
    print('after PATCH status=${rows.first['status']}');
    final c = await checkout(o['id'].toString());
    print('checkout: status=${c['status']} server=${c['server_amount_cents']} err=${c['error']}');
  } catch (e) {
    print('PATCH path error: $e');
  }

  // D) PATCH payment_method
  print('--- D PATCH payment_method ---');
  try {
    final o = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': productId,
        'price_total': 80.0,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'payment_method': 'Prémio da Rifa'},
      accessToken: buyerToken,
    );
    final rows = await sb.select('orders', filter: 'id=eq.${o['id']}', limit: 1);
    print('after PATCH pm=${rows.first['payment_method']}');
    final c = await checkout(o['id'].toString());
    print('checkout: status=${c['status']} server=${c['server_amount_cents']} err=${c['error']}');
  } catch (e) {
    print('PATCH pm error: $e');
  }

  try {
    await sb.deleteWhere('orders', 'product_id=eq.$productId');
    await sb.deleteWhere('products', 'id=eq.$productId');
  } catch (_) {}

  exit(0);
}
