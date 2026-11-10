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

  final app402 = await _analyze402(sb);
  final app403 = await _analyze403(sb);

  final summary = {
    'generated_at': DateTime.now().toIso8601String(),
    'app402': app402['summary'],
    'app403': app403['summary'],
  };

  await File('${outDir.path}/c19_contraditorio_402_403_summary.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(summary));
  await File('${outDir.path}/c19_contraditorio_402_raw.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(app402));
  await File('${outDir.path}/c19_contraditorio_403_raw.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(app403));

  print('APP-402 rule=${app402['summary']?['dominant_rule']}');
  print('APP-403 unresolved=${app403['summary']?['unresolved_count']}');
}

Future<Map<String, dynamic>> _analyze402(LiveOpsStagingClient sb) async {
  final soldOrders = await sb.select(
    'orders',
    filter:
        'status=in.(pago,enviado,concluido,premio_rifa)&order=created_at.desc',
    limit: 300,
  );
  final liveItemIds = soldOrders
      .map((o) => (o['live_item_id'] ?? '').toString())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();

  final rows = <Map<String, dynamic>>[];
  var matchOldRule = 0;
  var matchNewRule = 0;

  for (final id in liveItemIds.take(120)) {
    try {
      final raw = await sb.rpc('batata_live_item_stock', {'p_live_item_id': id});
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      if (m['ok'] != true) continue;
      final total = (m['total_qty'] as num?)?.toInt() ?? 0;
      final sold = (m['sold_converted_qty'] as num?)?.toInt() ?? 0;
      final available = (m['available_qty'] as num?)?.toInt() ?? 0;
      final blocked = (m['blocked_qty'] as num?)?.toInt() ?? 0;
      final accepted = (m['reserved_accepted_qty'] as num?)?.toInt() ?? 0;
      final pending = (m['pending_bag_qty'] as num?)?.toInt() ?? 0;

      final oldRule = _clamp(total - blocked - accepted - pending);
      final newRule = _clamp(total - blocked - accepted - pending - sold);
      final oldMatch = available == oldRule;
      final newMatch = available == newRule;
      if (oldMatch) matchOldRule++;
      if (newMatch) matchNewRule++;

      rows.add({
        'live_item_id': id,
        'product_id': m['product_id'],
        'ref_code': m['ref_code'],
        'item_kind': m['item_kind'],
        'total_qty': total,
        'blocked_qty': blocked,
        'reserved_accepted_qty': accepted,
        'pending_bag_qty': pending,
        'sold_converted_qty': sold,
        'available_qty': available,
        'available_by_old_rule': oldRule,
        'available_by_new_rule': newRule,
        'matches_old_rule': oldMatch,
        'matches_new_rule': newMatch,
      });
    } catch (_) {}
  }

  final anomalies = rows
      .where((r) =>
          (r['sold_converted_qty'] as int) > (r['total_qty'] as int) ||
          (r['available_qty'] as int) > (r['total_qty'] as int))
      .toList();

  final dominantRule = matchOldRule >= matchNewRule
      ? 'available = max(total - blocked - accepted - pending, 0)'
      : 'available = max(total - blocked - accepted - pending - sold, 0)';

  // extra context for anomalies: shared pool by product_id
  final byProduct = <String, int>{};
  for (final r in rows) {
    final pid = (r['product_id'] ?? '').toString();
    if (pid.isEmpty) continue;
    byProduct[pid] = (byProduct[pid] ?? 0) + 1;
  }

  return {
    'summary': {
      'sold_orders_considered': soldOrders.length,
      'live_items_sampled': rows.length,
      'old_rule_matches': matchOldRule,
      'new_rule_matches': matchNewRule,
      'dominant_rule': dominantRule,
      'anomaly_count': anomalies.length,
    },
    'rows': rows,
    'anomalies': anomalies.take(60).toList(),
    'shared_pool_counts_by_product_id': byProduct,
  };
}

Future<Map<String, dynamic>> _analyze403(LiveOpsStagingClient sb) async {
  final liveItems = await sb.select(
    'live_items',
    filter: 'item_kind=eq.marketplace_product&order=created_at.desc',
    limit: 160,
  );

  final rows = <Map<String, dynamic>>[];
  final unresolved = <Map<String, dynamic>>[];

  for (final li in liveItems) {
    final id = (li['id'] ?? '').toString();
    if (id.isEmpty) continue;
    final pid = (li['product_id'] ?? '').toString();
    if (pid.isEmpty) {
      final row = {
        'live_item_id': id,
        'product_id': pid,
        'classification': 'missing_product_id',
        'live_id': li['live_id'],
        'ref_code': li['ref_code'],
      };
      rows.add(row);
      unresolved.add(row);
      continue;
    }
    final p = await sb.select('products', filter: 'id=eq.$pid', limit: 1);
    if (p.isNotEmpty) {
      final pr = p.first;
      rows.add({
        'live_item_id': id,
        'product_id': pid,
        'classification': 'linked_ok',
        'live_ref_code': li['ref_code'],
        'product_ref_code': pr['ref_code'],
        'ref_match': (li['ref_code']?.toString() ?? '') ==
            (pr['ref_code']?.toString() ?? ''),
      });
      continue;
    }

    // not found in products -> investigate whether historical/orphan
    final orderUse = await sb.select(
      'orders',
      filter: 'product_id=eq.$pid&order=created_at.desc',
      limit: 3,
    );
    final cls = orderUse.isEmpty
        ? 'orphan_or_deleted_product_no_orders'
        : 'orphan_or_deleted_product_with_orders';
    final row = {
      'live_item_id': id,
      'product_id': pid,
      'classification': cls,
      'live_id': li['live_id'],
      'ref_code': li['ref_code'],
      'orders_sample': orderUse
          .map((o) => {
                'id': o['id'],
                'status': o['status'],
                'created_at': o['created_at'],
              })
          .toList(),
    };
    rows.add(row);
    unresolved.add(row);
  }

  final linked = rows.where((r) => r['classification'] == 'linked_ok').toList();
  final refMismatch = linked.where((r) => r['ref_match'] == false).toList();

  return {
    'summary': {
      'live_items_sampled': rows.length,
      'linked_ok_count': linked.length,
      'ref_mismatch_count': refMismatch.length,
      'unresolved_count': unresolved.length,
      'pass_strict': unresolved.isEmpty && refMismatch.isEmpty,
    },
    'rows': rows,
    'unresolved': unresolved,
  };
}

int _clamp(int n) => n < 0 ? 0 : n;
