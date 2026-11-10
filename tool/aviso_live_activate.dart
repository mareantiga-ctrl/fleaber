// ignore_for_file: avoid_print
/// Activa live scheduled existente (sem create Mux) p/ APP-218 + SEC-020.
///
/// Usa live com mux_live_id já alocado — quota diária está cheia (10/10).
/// No fim: dart run tool/aviso_live_end.dart
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _liveId = '3997db80-56be-4d2a-a9bc-7b8f359965d4';
const _fomoProductId = 'd275213c-e8c9-435f-8f74-be142c4b93f4'; // C27 Produto B qty=2
const _reportDir = 'tool/reports/battery_aviso_live_2026-08-23/bd';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');

  // End any other active leftovers first.
  final lives = await sb.select(
    'lives',
    filter: 'or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&order=created_at.desc',
    limit: 20,
  );
  for (final l in lives) {
    final id = l['id']?.toString() ?? '';
    if (id.isEmpty || id == _liveId) continue;
    final st = (l['status'] ?? '').toString().toLowerCase();
    if (l['is_active'] == true || st == 'live') {
      await sb.patch('lives', 'id=eq.$id', {
        'status': 'ended',
        'is_active': false,
      });
      print('ended leftover $id');
    }
  }

  await sb.patch('lives', 'id=eq.$_liveId', {
    'status': 'live',
    'is_active': true,
    'went_live_at': DateTime.now().toUtc().toIso8601String(),
    'ended_at': null,
  });
  print('activated live $_liveId');

  // Deactivate other items; activate/create FOMO item with available qty 2.
  await sb.patch('live_items', 'live_id=eq.$_liveId', {'is_active': false});

  final existingItems = await sb.select(
    'live_items',
    filter: 'live_id=eq.$_liveId&product_id=eq.$_fomoProductId',
    limit: 5,
  );

  String liveItemId;
  if (existingItems.isNotEmpty) {
    liveItemId = existingItems.first['id'].toString();
    final patch = <String, dynamic>{
      'is_active': true,
      'title': 'C27 Produto B',
    };
    // best-effort qty columns
    for (final col in ['available_qty', 'quantity', 'stock', 'qty_available']) {
      try {
        await sb.patch('live_items', 'id=eq.$liveItemId', {...patch, col: 2});
        print('patched live_item $liveItemId with $col=2');
        break;
      } catch (_) {}
    }
    await sb.patch('live_items', 'id=eq.$liveItemId', patch);
  } else {
    final inserted = await sb.insert('live_items', {
      'live_id': _liveId,
      'product_id': _fomoProductId,
      'seller_id': sellerId,
      'is_active': true,
      'title': 'C27 Produto B',
      'item_kind': 'marketplace_product',
      'available_qty': 2,
    });
    liveItemId = inserted['id'].toString();
    print('inserted live_item $liveItemId');
  }

  // Ensure product qty >= 2 for FOMO cross 2→1
  try {
    await sb.patch('products', 'id=eq.$_fomoProductId', {'quantity': 2});
  } catch (e) {
    print('product qty patch warn: $e');
  }

  final outDir = Directory(_reportDir);
  await outDir.create(recursive: true);
  final payload = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'live_id': _liveId,
    'live_item_id': liveItemId,
    'fomo_product_id': _fomoProductId,
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'note':
        'Reactivou live scheduled (mux_live_id já existia) — sem create-mux-live (quota 10/10).',
  };
  await File('${outDir.path}/live_active.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));

  final envLines = [
    'MAESTRO_LIVE_ID=$_liveId',
    'AVISO218_LIVE_ID=$_liveId',
    'AVISO218_LIVE_ITEM_ID=$liveItemId',
    'AVISO218_PRODUCT_ID=$_fomoProductId',
    'AVISO_SEC020_LIVE_ID=$_liveId',
    'AVISO_SEC020_LIVE_ITEM_ID=$liveItemId',
  ];
  await File('${outDir.path}/live.env').writeAsString(envLines.join('\n'));
  print(jsonEncode(payload));
}
