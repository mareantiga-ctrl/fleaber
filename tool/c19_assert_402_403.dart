// ignore_for_file: avoid_print
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

  final outDir = Directory('tool/reports/battery_c19_2026-08-19/bd');
  await outDir.create(recursive: true);

  final soldOrders = await sb.select(
    'orders',
    filter:
        'status=in.(pago,enviado,concluido,premio_rifa)&order=created_at.desc',
    limit: 250,
  );

  final soldLiveItemIds = soldOrders
      .map((o) => (o['live_item_id'] ?? '').toString())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();

  final app402Rows = <Map<String, dynamic>>[];
  for (final id in soldLiveItemIds.take(80)) {
    try {
      final raw = await sb.rpc('batata_live_item_stock', {'p_live_item_id': id});
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      if (m['ok'] != true) continue;
      final total = (m['total_qty'] as num?)?.toInt() ?? 0;
      final sold = (m['sold_converted_qty'] as num?)?.toInt() ?? 0;
      final available = (m['available_qty'] as num?)?.toInt() ?? 0;
      app402Rows.add({
        'live_item_id': id,
        'product_id': m['product_id'],
        'total_qty': total,
        'sold_converted_qty': sold,
        'available_qty': available,
        'invariant_ok': sold >= 0 && available >= 0 && total >= 0,
      });
    } catch (_) {}
  }

  final rowsSoldPositive =
      app402Rows.where((r) => (r['sold_converted_qty'] as int) > 0).toList();
  final invOk = app402Rows.every((r) => r['invariant_ok'] == true);

  // APP-403: verificar ligação de origem live -> marketplace_product.
  final liveItems = await sb.select(
    'live_items',
    filter: 'item_kind=eq.marketplace_product&order=created_at.desc',
    limit: 120,
  );
  final liveById = <String, Map<String, dynamic>>{
    for (final li in liveItems)
      if ((li['id'] ?? '').toString().isNotEmpty) (li['id']).toString(): li,
  };

  final products = await sb.select('products', filter: 'order=created_at.desc', limit: 400);
  final prodById = <String, Map<String, dynamic>>{
    for (final p in products)
      if ((p['id'] ?? '').toString().isNotEmpty) (p['id']).toString(): p,
  };

  final app403Rows = <Map<String, dynamic>>[];
  for (final li in liveItems) {
    final id = (li['id'] ?? '').toString();
    if (id.isEmpty) continue;
    final itemKind = (li['item_kind'] ?? '').toString();
    final pid = (li['product_id'] ?? '').toString();
    final p = prodById[pid];
    final linked = pid.isNotEmpty && p != null;
    final refLive = (li['ref_code'] ?? '').toString();
    final refProduct = (p?['ref_code'] ?? '').toString();
    final refMatch = linked && refLive.isNotEmpty && refProduct.isNotEmpty
        ? refLive == refProduct
        : true;
    app403Rows.add({
      'live_item_id': id,
      'item_kind': itemKind,
      'product_id': pid,
      'product_found': linked,
      'product_title': p?['title'],
      'ref_live': li['ref_code'],
      'ref_product': p?['ref_code'],
      'ref_match': refMatch,
    });
  }

  final soldMarketplace = app403Rows;
  final soldMarketplaceLinked =
      soldMarketplace.where((r) => r['product_found'] == true).toList();
  final soldMarketplaceRefMismatch =
      soldMarketplaceLinked.where((r) => r['ref_match'] == false).toList();

  final app402Pass = app402Rows.isNotEmpty && rowsSoldPositive.isNotEmpty && invOk;
  final app403Pass = soldMarketplace.isNotEmpty &&
      soldMarketplaceLinked.isNotEmpty &&
      soldMarketplaceRefMismatch.isEmpty;

  final result = {
    'generated_at': DateTime.now().toIso8601String(),
    'app402': {
      'pass': app402Pass,
      'sold_orders_considered': soldOrders.length,
      'live_items_sampled': app402Rows.length,
      'with_sold_converted_qty_gt_0': rowsSoldPositive.length,
      'invariants_ok': invOk,
      'sample_rows': rowsSoldPositive.take(20).toList(),
    },
    'app403': {
      'pass': app403Pass,
      'sold_marketplace_rows': soldMarketplace.length,
      'sold_marketplace_linked_rows': soldMarketplaceLinked.length,
      'sold_marketplace_ref_mismatch_rows': soldMarketplaceRefMismatch.length,
      'sample_rows': soldMarketplace.take(20).toList(),
    },
  };

  final outFile = File('${outDir.path}/c19_assert_402_403.json');
  await outFile.writeAsString(const JsonEncoder.withIndent('  ').convert(result));

  print('APP-402 pass=$app402Pass');
  print('APP-403 pass=$app403Pass');
  print('wrote ${outFile.path}');
}
