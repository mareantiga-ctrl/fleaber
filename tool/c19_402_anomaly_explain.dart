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

  final inFile = File('tool/reports/battery_c19_2026-08-19/bd/c19_contraditorio_402_raw.json');
  final raw = jsonDecode(await inFile.readAsString()) as Map<String, dynamic>;
  final rows = ((raw['rows'] as List?) ?? const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  final anomalies = rows
      .where((r) => ((r['sold_converted_qty'] as num?)?.toInt() ?? 0) >
          ((r['total_qty'] as num?)?.toInt() ?? 0))
      .toList();

  final out = <Map<String, dynamic>>[];
  for (final r in anomalies.take(12)) {
    final pid = (r['product_id'] ?? '').toString();
    if (pid.isEmpty) continue;

    final product = await sb.select('products', filter: 'id=eq.$pid', limit: 1);
    final liveItems = await sb.select('live_items', filter: 'product_id=eq.$pid&order=created_at.desc', limit: 20);
    final orders = await sb.select('orders', filter: 'product_id=eq.$pid&order=created_at.desc', limit: 80);
    final liIds = liveItems
        .map((e) => (e['id'] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .toList();
    final reqs = <Map<String, dynamic>>[];
    for (final liId in liIds.take(10)) {
      final part = await sb.select(
        'live_reservation_requests',
        filter: 'live_item_id=eq.$liId&order=created_at.desc',
        limit: 30,
      );
      reqs.addAll(part);
    }

    final orderByStatus = <String, int>{};
    var soldStatusesQty = 0;
    var blockedStatusesQty = 0;
    for (final o in orders) {
      final status = (o['status'] ?? '').toString().trim().toLowerCase();
      final qty = (o['quantity'] as num?)?.toInt() ?? 1;
      orderByStatus[status] = (orderByStatus[status] ?? 0) + qty;
      if (status == 'pago' || status == 'paid' || status == 'enviado' || status == 'concluido' || status == 'concluído' || status == 'entregue') {
        soldStatusesQty += qty;
      }
      if (status == 'reservado' || status == 'aguarda_confirmacao' || status == 'pendente' || status == 'pedido_devolucao' || status == 'em_devolucao' || status == 'pago' || status == 'enviado') {
        blockedStatusesQty += qty;
      }
    }

    final reqByStatus = <String, int>{};
    for (final rq in reqs) {
      final status = (rq['status'] ?? '').toString();
      final qty = (rq['requested_qty'] as num?)?.toInt() ?? 1;
      reqByStatus[status] = (reqByStatus[status] ?? 0) + qty;
    }

    out.add({
      'live_item_id': r['live_item_id'],
      'product_id': pid,
      'rpc_total_qty': r['total_qty'],
      'rpc_sold_converted_qty': r['sold_converted_qty'],
      'rpc_available_qty': r['available_qty'],
      'rpc_blocked_qty': r['blocked_qty'],
      'product_quantity_now': product.isEmpty ? null : product.first['quantity'],
      'live_items_with_same_product': liveItems.length,
      'orders_count': orders.length,
      'orders_qty_by_status': orderByStatus,
      'orders_qty_sold_statuses': soldStatusesQty,
      'orders_qty_blocked_statuses': blockedStatusesQty,
      'reservation_qty_by_status': reqByStatus,
    });
  }

  final file = File('tool/reports/battery_c19_2026-08-19/bd/c19_402_anomaly_explain_raw.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
    'generated_at': DateTime.now().toIso8601String(),
    'anomalies_analyzed': out.length,
    'rows': out,
  }));

  print('anomalies explained: ${out.length}');
}
