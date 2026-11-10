// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final buyer = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final seller = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  final orders = await sb.select(
    'orders',
    filter:
        'buyer_id=eq.$buyer&seller_id=eq.$seller&status=eq.pago&order=created_at.desc',
    limit: 30,
  );
  final out = [];
  for (final o in orders) {
    out.add({
      'id': o['id'],
      'price': o['price_total'],
      'payment_method': o['payment_method'],
      'product_id': o['product_id'],
      'created_at': o['created_at'],
      'is_reservation': o['is_reservation'],
    });
  }

  // Regression product stock
  final prodId = '9d0c3ef1-983f-4ee9-8686-902141e727a0';
  final products = await sb.select('products', filter: 'id=eq.$prodId', limit: 1);
  print(jsonEncode({
    'pago_orders': out,
    'regression_product': products.isEmpty ? null : {
      'id': products.first['id'],
      'title': products.first['title'] ?? products.first['name'],
      'stock': products.first['stock'] ?? products.first['quantity'],
      'price': products.first['price'],
      'status': products.first['status'],
    },
  }));
}
