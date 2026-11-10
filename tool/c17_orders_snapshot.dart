// ignore_for_file: avoid_print
/// Snapshot C17: encomendas por estado, produtos com sold_count.
library;

import 'dart:convert';
import 'dart:io';
import 'live_ops_staging_client.dart';

void main(List<String> args) async {
  final staging = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final orders = await sb.select(
    'orders',
    filter: 'order=created_at.desc',
    limit: 50,
  );

  final Map<String, List<Map>> byStatus = {};
  for (final o in orders) {
    final s = o['status'] as String? ?? 'unknown';
    byStatus.putIfAbsent(s, () => []).add(o);
  }

  print('=== ORDERS BY STATUS ===');
  for (final entry in byStatus.entries) {
    print('${entry.key}: ${entry.value.length}');
    for (final o in entry.value.take(2)) {
      print('  id=${o['id']} total=${o['total_price']} created=${o['created_at']}');
    }
  }

  final prods = await sb.select(
    'products',
    filter: 'sold_count=gt.0&order=sold_count.desc',
    limit: 10,
  );

  print('\n=== PRODUCTS WITH SOLD_COUNT > 0 ===');
  for (final p in prods) {
    print('  id=${p['id']} title=${p['title']} stock=${p['stock_quantity']} sold=${p['sold_count']} price=${p['price']} active=${p['is_active']}');
  }

  final outDir = Directory('tool/reports/battery_c17_2026-08-19/bd');
  await outDir.create(recursive: true);
  final outFile = File('tool/reports/battery_c17_2026-08-19/bd/c17_orders_pre.json');
  await outFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert({'orders_by_status': byStatus, 'products_sold': prods}),
  );
  print('\nwrote ${outFile.path}');
}
