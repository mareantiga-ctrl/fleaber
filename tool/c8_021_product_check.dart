// ignore_for_file: avoid_print
/// APP-021 — estado do anúncio taça cerâmica U / U C8.
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
  const id = 'e6411e97-c9f1-4a6c-99fd-ee79d5e3caee';
  final rows = await client.select('products', filter: 'id=eq.$id', limit: 1);
  if (rows.isEmpty) {
    print('MISSING product $id');
    return;
  }
  final p = rows.first;
  print(const JsonEncoder.withIndent('  ').convert({
    'id': p['id'],
    'title': p['title'],
    'price': p['price'],
    'qty': p['quantity'],
    'sold': p['is_sold'],
    'listed': p['list_on_marketplace'],
    'image_urls': p['image_urls'],
  }));
}
