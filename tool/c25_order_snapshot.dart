// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  final oid = args.isEmpty ? 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae' : args.first;
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final rows = await sb.select('orders', filter: 'id=eq.$oid', limit: 1);
  if (rows.isEmpty) {
    print('order not found');
    exit(1);
  }
  final o = rows.first;
  final disputes = await sb.select(
    'order_disputes',
    filter: 'order_id=eq.$oid',
    limit: 5,
  );
  print(jsonEncode({
    'order': o,
    'disputes': disputes,
  }));
}
