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
  final buyer = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final seller = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  final reqs = await sb.select(
    'live_reservation_requests',
    filter: 'order=created_at.desc',
    limit: 40,
  );
  final mine = reqs.where((r) {
    final b = (r['buyer_id'] ?? r['user_id'] ?? '').toString();
    final s = (r['seller_id'] ?? '').toString();
    return b == buyer || s == seller;
  }).toList();

  // also live_items with stock on recent ended lives? 
  final items = await sb.select(
    'live_items',
    filter: 'order=created_at.desc',
    limit: 20,
  );

  final out = {
    'requests_total': reqs.length,
    'requests_relevant': mine.take(15).toList(),
    'sample_request_keys': reqs.isEmpty ? [] : reqs.first.keys.toList(),
    'live_items_sample': items.take(8).map((i) => {
          'id': i['id'],
          'live_id': i['live_id'],
          'product_id': i['product_id'],
          'status': i['status'],
          'qty': i['quantity'] ?? i['qty_available'] ?? i['stock'],
          'title': i['title'] ?? i['name'],
        }).toList(),
  };
  await File('tool/reports/battery_c26_2026-08-22/bd/c26_app061_queue.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode({
    'reqs': reqs.length,
    'relevant': mine.length,
    'pending': mine.where((r) => (r['status'] ?? '') == 'pending').length,
    'accepted': mine.where((r) => (r['status'] ?? '') == 'accepted').length,
    'first_pending': mine
        .where((r) => (r['status'] ?? '') == 'pending')
        .map((r) => r['id'])
        .take(3)
        .toList(),
  }));
}
