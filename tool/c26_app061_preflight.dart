// ignore_for_file: avoid_print
/// C26 — APP-061 preflight: reservado / filas live / lives activos.
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

  final reservado = await sb.select(
    'orders',
    filter:
        'buyer_id=eq.$buyer&seller_id=eq.$seller&status=eq.reservado&order=created_at.desc',
    limit: 10,
  );

  final livesActive = await sb.select(
    'lives',
    filter: 'seller_id=eq.$seller&is_active=eq.true&order=created_at.desc',
    limit: 10,
  );

  // reservation queue / bag rows if table exists
  List<Map<String, dynamic>> queue = [];
  try {
    queue = await sb.select(
      'live_item_reservations',
      filter: 'order=created_at.desc',
      limit: 30,
    );
  } catch (_) {
    try {
      queue = await sb.select(
        'live_reservations',
        filter: 'order=created_at.desc',
        limit: 30,
      );
    } catch (e) {
      queue = [
        {'error': e.toString()}
      ];
    }
  }

  // products with stock from seller
  final products = await sb.select(
    'products',
    filter: 'seller_id.eq.$seller&order=created_at.desc',
    limit: 15,
  );

  final out = {
    'buyer': buyer,
    'seller': seller,
    'reservado_orders': reservado
        .map((o) => {
              'id': o['id'],
              'status': o['status'],
              'product_id': o['product_id'],
              'live_id': o['live_id'],
              'price_total': o['price_total'],
              'created_at': o['created_at'],
              'is_reservation': o['is_reservation'],
            })
        .toList(),
    'active_lives': livesActive
        .map((l) => {
              'id': l['id'],
              'title': l['title'] ?? l['name'],
              'status': l['status'],
              'is_active': l['is_active'],
              'mux_playback_id': l['mux_playback_id'],
            })
        .toList(),
    'queue_sample': queue.take(10).toList(),
    'products_sample': products
        .take(8)
        .map((p) => {
              'id': p['id'],
              'title': p['title'] ?? p['name'],
              'stock': p['stock'] ?? p['quantity'],
              'price': p['price'],
            })
        .toList(),
  };

  final dir = Directory('tool/reports/battery_c26_2026-08-22/bd');
  await dir.create(recursive: true);
  await File('${dir.path}/c26_app061_preflight.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode({
    'reservado_count': reservado.length,
    'active_lives': livesActive.length,
    'first_reservado': reservado.isEmpty ? null : reservado.first['id'],
    'first_live': livesActive.isEmpty ? null : livesActive.first['id'],
  }));
}
