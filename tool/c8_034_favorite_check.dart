// ignore_for_file: avoid_print
library;

import 'dart:convert';

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const buyer = '7848848c-92df-4341-ad2a-7a5c24f1c250';
  const product = 'e6411e97-c9f1-4a6c-99fd-ee79d5e3caee';
  final rows = await client.select(
    'favorites',
    filter: 'user_id=eq.$buyer&product_id=eq.$product',
    limit: 5,
  );
  print(const JsonEncoder.withIndent('  ').convert({
    'count': rows.length,
    'rows': rows,
  }));
}
