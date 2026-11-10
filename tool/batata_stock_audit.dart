// ignore_for_file: avoid_print
/// Diagnóstico BATATA_STOCK — products + encomendas pagas recentes (sem pedir logs ao QA).
///
/// Uso:
///   dart run tool/batata_stock_audit.dart
///   dart run tool/batata_stock_audit.dart --title Espelho
///   dart run tool/batata_stock_audit.dart --title Jarra --title Espelho
///   dart run tool/batata_stock_audit.dart --product-id UUID
library;

import 'dart:io';

import 'live_ops_staging_client.dart';
import 'regression/staging_guard.dart';

Future<void> main(List<String> args) async {
  final titleFilters = <String>[];
  final productIds = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--title' && i + 1 < args.length) {
      titleFilters.add(args[++i]);
    } else if (args[i] == '--product-id' && i + 1 < args.length) {
      productIds.add(args[++i]);
    }
  }

  Map<String, String> env;
  try {
    env = loadLiveOpsStagingEnv();
  } catch (e) {
    print('SKIP_CONFIG: $e');
    exit(3);
  }

  final guard = RegressionStagingGuard.check(env);
  if (!guard.ok) {
    print('SKIP_CONFIG: ${guard.reason}');
    exit(3);
  }

  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  print('=== BATATA_STOCK audit ===');
  print('project: ${client.url}');
  print('');

  // 1) Products by title or id
  print('--- products ---');
  var products = <Map<String, dynamic>>[];
  if (productIds.isNotEmpty) {
    for (final id in productIds) {
      final rows = await client.select(
        'products',
        filter: 'id=eq.$id',
        limit: 1,
      );
      products.addAll(rows);
    }
  } else if (titleFilters.isNotEmpty) {
    for (final t in titleFilters) {
      final enc = Uri.encodeComponent('*$t*');
      final rows = await client.select(
        'products',
        filter: 'title=ilike.$enc',
        limit: 10,
      );
      products.addAll(rows);
    }
  } else {
    products = await client.select(
      'products',
      filter: 'order=updated_at.desc',
      limit: 8,
    );
  }

  if (products.isEmpty) {
    print('(nenhum produto encontrado — ajusta --title ou --product-id)');
  }
  for (final p in products) {
    final id = p['id'];
    final title = p['title'];
    final qty = p['quantity'];
    final sold = p['is_sold'];
    final list = p['list_on_marketplace'];
    print(
      'product=$id title="$title" quantity=$qty is_sold=$sold '
      'list_on_marketplace=$list',
    );

    final orders = await client.select(
      'orders',
      filter: 'product_id=eq.$id&order=created_at.desc',
      limit: 5,
    );
    for (final o in orders) {
      print(
        '  order=${o['id']} status=${o['status']} qty=${o['quantity']} '
        'bundle_id=${o['bundle_id'] ?? '—'} total=${o['price_total']}',
      );
    }
  }

  print('');
  print('--- trigger (esperado em staging) ---');
  print('batata_mark_product_sold_on_paid_order: decrementa quantity;');
  print('is_sold/list_on_marketplace=false só quando quantity=0.');
  print('batata_restore_product_stock_on_cancelled_order: pago/enviado→cancelado repõe qty;');
  print('CHECK products_quantity_check deve permitir quantity >= 0.');
  print('');
  print('Logs Supabase: filtrar "BATATA_STOCK" (Postgres + Edge create-payment-intent).');
  print('Flutter: filtrar "BATATA_STOCK payBundleNow" / BATATA_CANCEL_RELIST no logcat.');
}
