// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL'));
  final client = LiveOpsStagingClient(
    url: url,
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const seller = '980f4fa1-0004-42f9-abca-69f1a9c29588';

  final profiles = await client.select(
    'profiles',
    filter: 'id=eq.$seller',
    limit: 1,
  );
  final products = await client.select(
    'products',
    filter: 'seller_id=eq.$seller&order=created_at.desc',
    limit: 30,
  );
  final reviews = await client.select(
    'reviews',
    filter: 'target_id=eq.$seller&order=created_at.desc',
    limit: 20,
  );
  final lives = await client.select(
    'lives',
    filter: 'seller_id=eq.$seller&order=created_at.desc',
    limit: 8,
  );

  Map<String, dynamic> slimProduct(Map<String, dynamic> r) => {
        'id': r['id'],
        'name': r['name'] ?? r['title'],
        'price': r['price'],
        'list_on_marketplace': r['list_on_marketplace'],
        'is_sold': r['is_sold'],
        'quantity': r['quantity'] ?? r['qty'],
        'created_at': r['created_at'],
      };

  Map<String, dynamic> slimLive(Map<String, dynamic> r) => {
        'id': r['id'],
        'title': r['title'] ?? r['name'],
        'status': r['status'],
        'is_active': r['is_active'],
        'mux_playback_id': r['mux_playback_id'],
        'ended_at': r['ended_at'],
        'created_at': r['created_at'],
      };

  final listed = await client.select(
    'products',
    filter:
        'seller_id=eq.$seller&list_on_marketplace=eq.true&is_sold=eq.false&order=created_at.desc',
    limit: 80,
  );

  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'seller_id': seller,
    'profile': profiles.isEmpty
        ? null
        : {
            'full_name': profiles.first['full_name'],
            'handle': profiles.first['handle'],
            'hub_published': profiles.first['hub_published'],
          },
    'products_head': products.take(12).map(slimProduct).toList(),
    'listed_count': listed.length,
    'listed_names': listed
        .map((p) => '${p['name'] ?? p['title']} ${p['price']}€')
        .take(12)
        .toList(),
    'reviews': reviews
        .map((r) => {
              'id': r['id'],
              'stars': r['stars'] ?? r['rating'],
              'created_at': r['created_at'],
            })
        .toList(),
    'lives_head': lives.map(slimLive).toList(),
    'active_lives': lives
        .where((l) => l['is_active'] == true || l['status'] == 'live')
        .map(slimLive)
        .toList(),
  };

  final dir = Directory('tool/reports/battery_c10_2026-08-18/evidence');
  dir.createSync(recursive: true);
  final file = File('${dir.path}/c10_hub_snapshot.json');
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print('wrote ${file.path}');
  print(const JsonEncoder.withIndent('  ').convert({
    'handle': (out['profile'] as Map?)?['handle'],
    'hub_published': (out['profile'] as Map?)?['hub_published'],
    'listed_count': out['listed_count'],
    'listed_names': out['listed_names'],
    'reviews': (out['reviews'] as List).length,
    'active_lives': (out['active_lives'] as List).length,
  }));
}
