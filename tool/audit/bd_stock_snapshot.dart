// Snapshot BD com stock RPC por live_item.
import 'dart:convert';
import 'dart:io';

import '../bot_sim/report/db_snapshot.dart';
import '../live_ops_staging_client.dart';
import 'models.dart';

const stockFields = [
  'total_qty',
  'available_qty',
  'reserved_qty',
  'sold_qty',
  'blocked_qty',
  'cross_reserved_qty',
  'sold_converted_qty',
];

class BdStockSnapshot {
  BdStockSnapshot(this.client);

  final LiveOpsStagingClient client;

  static int? _int(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static QtySnapshot fromRpcMap(
    Map<String, dynamic> map, {
    required String source,
    required String liveItemId,
  }) {
    final sold = _int(map['sold']) ?? _int(map['sold_qty']);
    return QtySnapshot(
      totalQty: _int(map['total_qty']),
      availableQty: _int(map['available_qty']),
      reservedQty: _int(map['reserved_qty']),
      soldQty: sold,
      blockedQty: _int(map['blocked_qty']),
      crossReservedQty: _int(map['cross_reserved_qty']),
      soldConvertedQty:
          _int(map['sold_converted_qty']) ?? _int(map['sold_converted']),
      source: source,
      liveItemId: liveItemId,
      raw: map,
    );
  }

  Future<Map<String, dynamic>> capture({
    required String liveId,
    String label = 'bd_snapshot',
  }) async {
    final base = await DbSnapshotter(client).capture(liveId: liveId);
    final items = (base['live_items'] as List?) ?? [];
    final stockByItem = <String, dynamic>{};
    final snapshots = <QtySnapshot>[];

    for (final raw in items) {
      if (raw is! Map) continue;
      final itemId = raw['id']?.toString() ?? '';
      if (itemId.isEmpty) continue;
      try {
        final rpc = await client.rpc('batata_live_item_stock', {
          'p_live_item_id': itemId,
        });
        if (rpc is Map) {
          final m = Map<String, dynamic>.from(rpc);
          stockByItem[itemId] = m;
          snapshots.add(fromRpcMap(m, source: 'bd_rpc', liveItemId: itemId));
        }
      } catch (e) {
        stockByItem[itemId] = {'error': e.toString()};
      }
    }

    return {
      ...base,
      'label': label,
      'stock_rpc_by_live_item_id': stockByItem,
      'stock_snapshots': snapshots.map((s) => s.toJson()).toList(),
      'queries': [
        'select * from lives where id=eq.$liveId',
        'select * from live_items where live_id=eq.$liveId',
        'rpc batata_live_item_stock(p_live_item_id) per item',
      ],
    };
  }

  Future<String> writeSnapshot({
    required String liveId,
    required Directory outDir,
    String label = 'bd_snapshot',
  }) async {
    outDir.createSync(recursive: true);
    final data = await capture(liveId: liveId, label: label);
    final file = File('${outDir.path}/$label.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file.path;
  }
}
