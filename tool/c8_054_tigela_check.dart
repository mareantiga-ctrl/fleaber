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
  const seller = '980f4fa1-0004-42f9-abca-69f1a9c29588';
  final rows = await client.select(
    'products',
    filter: 'seller_id=eq.$seller&title=eq.tigela cerâmica Y&order=created_at.desc',
    limit: 8,
  );
  print(const JsonEncoder.withIndent('  ').convert(rows.map((p) {
        return {
          'id': p['id'],
          'created_at': p['created_at'],
          'sold': p['is_sold'],
          'listed': p['list_on_marketplace'],
          'ref': p['ref_code'],
          'price': p['price'],
        };
      }).toList()));
}
