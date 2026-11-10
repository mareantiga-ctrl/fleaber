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
  const seller = '980f4fa1-0004-42f9-abca-69f1a9c29588';
  final rows = await client.select(
    'follows',
    filter: 'follower_id=eq.$buyer&following_id=eq.$seller',
    limit: 5,
  );
  print('follows=${rows.length}');
  print(const JsonEncoder.withIndent('  ').convert(rows));
  final reviews = await client.select(
    'reviews',
    filter: 'target_id=eq.$seller&order=created_at.desc',
    limit: 5,
  );
  print('reviews=${reviews.length}');
  print(const JsonEncoder.withIndent('  ').convert(reviews.map((r) {
        return {
          'id': r['id'],
          'stars': r['stars'] ?? r['rating'],
          'created_at': r['created_at'],
        };
      }).toList()));
}
