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

  await _exportChatKindCounts(sb, outDir);
  await _exportApp402StockEvidence(sb, outDir);
  await _exportApp403OriginEvidence(sb, outDir);

  print('ok: raw exports em ${outDir.path}');
}

Future<void> _exportChatKindCounts(
  LiveOpsStagingClient sb,
  Directory outDir,
) async {
  final msgs = await sb.select(
    'chat_messages',
    filter: 'text=like.FLEABER_JSON_V1%25&order=created_at.desc',
    limit: 300,
  );
  const prefix = 'FLEABER_JSON_V1:';
  final Map<String, List<Map<String, dynamic>>> byKind = {};

  for (final m in msgs) {
    final text = (m['text'] ?? '').toString();
    if (!text.startsWith(prefix)) continue;
    try {
      final payload = jsonDecode(text.substring(prefix.length));
      if (payload is! Map) continue;
      final kind = (payload['kind'] ?? 'unknown').toString();
      byKind.putIfAbsent(kind, () => []);
      byKind[kind]!.add({
        'id': m['id'],
        'chat_id': m['chat_id'],
        'created_at': m['created_at'],
      });
    } catch (_) {}
  }

  final out = <String, dynamic>{
    'generated_at': DateTime.now().toIso8601String(),
    'source': 'chat_messages.text like FLEABER_JSON_V1%',
    'counts': {
      for (final e in byKind.entries) e.key: e.value.length,
    },
    'samples': {
      for (final e in byKind.entries) e.key: e.value.take(5).toList(),
    },
  };
  await File('${outDir.path}/c19_c18_chat_kind_counts_raw.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
}

Future<void> _exportApp402StockEvidence(
  LiveOpsStagingClient sb,
  Directory outDir,
) async {
  final liveItems = await sb.select(
    'live_items',
    filter: 'order=created_at.desc',
    limit: 60,
  );

  final products = await sb.select(
    'products',
    filter: 'order=created_at.desc',
    limit: 120,
  );
  final productsById = <String, Map<String, dynamic>>{
    for (final p in products)
      if ((p['id'] ?? '').toString().isNotEmpty) (p['id']).toString(): p,
  };

  final stockRows = <Map<String, dynamic>>[];
  for (final li in liveItems) {
    final id = (li['id'] ?? '').toString();
    if (id.isEmpty) continue;
    try {
      final raw = await sb.rpc('batata_live_item_stock', {'p_live_item_id': id});
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      if (m['ok'] != true) continue;
      final sold = (m['sold_converted_qty'] as num?)?.toInt() ?? 0;
      final total = (m['total_qty'] as num?)?.toInt() ?? 0;
      final available = (m['available_qty'] as num?)?.toInt() ?? 0;
      final reservedAccepted = (m['reserved_accepted_qty'] as num?)?.toInt() ?? 0;
      final pendingBag = (m['pending_bag_qty'] as num?)?.toInt() ?? 0;
      if (sold <= 0 && (available == total) && reservedAccepted <= 0 && pendingBag <= 0) {
        continue;
      }
      final productId = (m['product_id'] ?? '').toString();
      final p = productsById[productId];
      stockRows.add({
        'live_item_id': id,
        'live_id': m['live_id'],
        'title': m['title'] ?? li['title'],
        'item_kind': m['item_kind'],
        'product_id': productId,
        'ref_code': m['ref_code'],
        'total_qty': total,
        'sold_converted_qty': sold,
        'reserved_accepted_qty': reservedAccepted,
        'pending_bag_qty': pendingBag,
        'available_qty': available,
        'product_snapshot': p == null
            ? null
            : {
                'id': p['id'],
                'title': p['title'],
                'list_on_marketplace': p['list_on_marketplace'],
                'quantity': p['quantity'],
                'is_sold': p['is_sold'],
                'seller_id': p['seller_id'],
              },
      });
    } catch (_) {}
  }

  final out = <String, dynamic>{
    'generated_at': DateTime.now().toIso8601String(),
    'source_rpc': 'batata_live_item_stock',
    'rule': 'APP-402 usa sold_converted_qty/available_qty da RPC, não products.sold_count',
    'rows': stockRows,
    'rows_count': stockRows.length,
    'rows_with_sold_converted_qty_gt_0':
        stockRows.where((r) => ((r['sold_converted_qty'] as int?) ?? 0) > 0).length,
  };

  await File('${outDir.path}/c19_app402_stock_raw.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));

  // Complemento APP-402: partir de encomendas já pagas/enviadas/concluídas
  final soldOrders = await sb.select(
    'orders',
    filter:
        'status=in.(pago,enviado,concluido,premio_rifa)&order=created_at.desc',
    limit: 200,
  );
  final liveItemIds = soldOrders
      .map((o) => (o['live_item_id'] ?? '').toString())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();

  final soldLinked = <Map<String, dynamic>>[];
  for (final id in liveItemIds.take(60)) {
    try {
      final raw = await sb.rpc('batata_live_item_stock', {'p_live_item_id': id});
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      if (m['ok'] != true) continue;
      soldLinked.add({
        'live_item_id': id,
        'title': m['title'],
        'item_kind': m['item_kind'],
        'total_qty': m['total_qty'],
        'sold_converted_qty': m['sold_converted_qty'],
        'available_qty': m['available_qty'],
        'reserved_accepted_qty': m['reserved_accepted_qty'],
        'pending_bag_qty': m['pending_bag_qty'],
        'product_id': m['product_id'],
      });
    } catch (_) {}
  }

  await File('${outDir.path}/c19_app402_stock_from_sold_orders_raw.json')
      .writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'generated_at': DateTime.now().toIso8601String(),
      'source_orders_statuses': ['pago', 'enviado', 'concluido', 'premio_rifa'],
      'live_item_ids_count': liveItemIds.length,
      'rows': soldLinked,
      'rows_count': soldLinked.length,
      'rows_with_sold_converted_qty_gt_0': soldLinked
          .where((r) => ((r['sold_converted_qty'] as num?)?.toInt() ?? 0) > 0)
          .length,
    }),
  );
}

Future<void> _exportApp403OriginEvidence(
  LiveOpsStagingClient sb,
  Directory outDir,
) async {
  final liveMarketplace = await sb.select(
    'live_items',
    filter: 'item_kind=eq.marketplace_product&order=created_at.desc',
    limit: 80,
  );
  final products = await sb.select(
    'products',
    filter: 'order=created_at.desc',
    limit: 200,
  );

  final productsById = <String, Map<String, dynamic>>{
    for (final p in products)
      if ((p['id'] ?? '').toString().isNotEmpty) (p['id']).toString(): p,
  };

  final rows = <Map<String, dynamic>>[];
  for (final li in liveMarketplace) {
    final pid = (li['product_id'] ?? '').toString();
    if (pid.isEmpty) continue;
    final p = productsById[pid];
    rows.add({
      'live_item_id': li['id'],
      'live_id': li['live_id'],
      'item_kind': li['item_kind'],
      'live_ref_code': li['ref_code'],
      'product_id': pid,
      'product_found': p != null,
      'product_title': p?['title'],
      'product_ref_code': p?['ref_code'],
      'product_list_on_marketplace': p?['list_on_marketplace'],
      'product_seller_id': p?['seller_id'],
    });
  }

  final validLinks = rows.where((r) => r['product_found'] == true).length;

  final out = <String, dynamic>{
    'generated_at': DateTime.now().toIso8601String(),
    'source': 'live_items(item_kind=marketplace_product) + products',
    'total_rows': rows.length,
    'linked_rows': validLinks,
    'rows': rows.take(40).toList(),
  };

  await File('${outDir.path}/c19_app403_origin_raw.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
}
