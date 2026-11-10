// ignore_for_file: avoid_print
/// Dump BD após reteste copy C6 (item A esgotado + reservas B/C).
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const liveId = '86457b9d-9dfd-46af-b497-49418bc1ac6e';
  const itemA = 'fd57c4ab-ffa7-4e0e-a768-a3ffabbd8bca';

  final live = await client.select('lives', filter: 'id=eq.$liveId', limit: 1);
  final items = await client.select(
    'live_items',
    filter: 'live_id=eq.$liveId',
    limit: 10,
  );
  final reservas = await client.select(
    'live_reservation_requests',
    filter: 'live_id=eq.$liveId',
    limit: 20,
  );
  final stock = await client.rpc('batata_live_item_stock', {
    'p_live_item_id': itemA,
  });

  final outDir = Directory('tool/reports/battery_c6_2026-08-17/bd');
  outDir.createSync(recursive: true);
  File('${outDir.path}/c6_retest_live.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(live));
  File('${outDir.path}/c6_retest_items.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(items));
  File('${outDir.path}/c6_retest_reservas.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(reservas));
  File('${outDir.path}/c6_retest_item_a_stock.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(stock));

  final a = items.cast<Map<String, dynamic>>().firstWhere(
        (e) => e['id']?.toString() == itemA,
        orElse: () => <String, dynamic>{},
      );
  print('live status=${live.first['status']} active=${live.first['is_active']}');
  print('item A status=${a['status']} title=${a['title']}');
  print('stock A $stock');
  for (final r in reservas) {
    print(
      'reserva ${r['id']} item=${r['live_item_id']} status=${r['status']} qty=${r['requested_qty']}',
    );
  }
}
