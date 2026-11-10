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

  final pending = await sb.select(
    'orders',
    filter:
        'buyer_id=eq.$buyer&seller_id=eq.$seller&status=eq.reserva_pendente&order=created_at.desc',
    limit: 20,
  );
  final out = {
    'count': pending.length,
    'orders': pending
        .map((o) => {
              'id': o['id'],
              'product_id': o['product_id'],
              'price_total': o['price_total'],
              'created_at': o['created_at'],
              'live_id': o['live_id'],
              'payment_method': o['payment_method'],
            })
        .toList(),
  };
  await File('tool/reports/battery_c26_2026-08-22/bd/c26_app061_reserva_pendente.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
}
