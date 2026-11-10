// ignore_for_file: avoid_print
/// Preflight live APP-218 + SEC-020 — estado lives + itens stock.
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
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');

  final lives = await sb.select(
    'lives',
    filter: 'or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&order=created_at.desc',
    limit: 15,
  );

  final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  var createdToday = 0;
  final active = <Map<String, dynamic>>[];
  for (final l in lives) {
    final created = (l['created_at'] ?? '').toString();
    if (created.startsWith(today)) createdToday++;
    final st = (l['status'] ?? '').toString().toLowerCase();
    final isActive = l['is_active'] == true;
    if (isActive || st == 'live' || st == 'active' || st == 'starting') {
      active.add(l);
    }
  }

  print('seller=$sellerId buyer=$buyerId');
  print('lives_created_today≈$createdToday (Mux quota tipicamente 10)');
  print('active_or_live_count=${active.length}');
  for (final l in active) {
    print(' ACTIVE ${l['id']} status=${l['status']} active=${l['is_active']} title=${l['title']}');
  }
  print('--- recent lives ---');
  for (final l in lives.take(8)) {
    print(' ${l['id']} status=${l['status']} active=${l['is_active']} created=${l['created_at']} title=${l['title']}');
  }

  // Products with qty suitable for FOMO (available >1 or =1)
  final products = await sb.select(
    'products',
    filter: 'seller_id.eq.$sellerId&order=updated_at.desc.nullslast',
    limit: 30,
  );
  print('--- products sample ---');
  for (final p in products.take(12)) {
    print(' ${p['id']} qty=${p['quantity'] ?? p['stock'] ?? p['available_qty']} title=${p['title']}');
  }

  final outDir = Directory('tool/reports/battery_aviso_live_2026-08-23/bd');
  await outDir.create(recursive: true);
  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'lives_created_today': createdToday,
    'active_lives': active,
    'recent_lives': lives.take(8).toList(),
  };
  await File('${outDir.path}/preflight_live.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('wrote ${outDir.path}/preflight_live.json');
}
