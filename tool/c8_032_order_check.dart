// ignore_for_file: avoid_print
library;

import 'dart:convert';

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const buyer = '7848848c-92df-4341-ad2a-7a5c24f1c250';
  const product = 'e6411e97-c9f1-4a6c-99fd-ee79d5e3caee';
  final orders = await client.select(
    'orders',
    filter: 'buyer_id=eq.$buyer&order=created_at.desc',
    limit: 6,
  );
  print('--- buyer orders ---');
  print(const JsonEncoder.withIndent('  ').convert(orders.map((o) {
        return {
          'id': o['id'],
          'status': o['status'],
          'product_id': o['product_id'],
          'c8': o['product_id'] == product,
          'shipping': o['shipping_method'],
          'payment': o['payment_method'],
          'qty': o['quantity'],
          'created_at': o['created_at'],
        };
      }).toList()));

  final c8 = await client.select(
    'products',
    filter: 'id=eq.$product',
    limit: 1,
  );
  if (c8.isNotEmpty) {
    final p = c8.first;
    print('--- C8 product ---');
    print(const JsonEncoder.withIndent('  ').convert({
      'title': p['title'],
      'qty': p['quantity'],
      'sold': p['is_sold'],
      'listed': p['list_on_marketplace'],
    }));
  }
}
