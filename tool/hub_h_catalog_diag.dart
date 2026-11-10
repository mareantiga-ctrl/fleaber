// ignore_for_file: avoid_print
/// Diagnóstico: quantos produtos available_for_live + live_items em draft/live recente.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final sellerId = '980f4fa1-0004-42f9-abca-69f1a9c29588';

  final on = await client.select(
    'products',
    filter: 'seller_id=eq.$sellerId&available_for_live=eq.true&is_sold=eq.false',
    limit: 300,
  );
  final off = await client.select(
    'products',
    filter: 'seller_id=eq.$sellerId&available_for_live=eq.false&is_sold=eq.false',
    limit: 300,
  );

  final drafts = await client.select(
    'lives',
    filter:
        'or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&status=eq.draft&order=created_at.desc',
    limit: 5,
  );

  final recent = await client.select(
    'lives',
    filter:
        'or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&order=created_at.desc',
    limit: 5,
  );

  Future<int> countItems(String liveId) async {
    final rows = await client.select(
      'live_items',
      filter: 'live_id=eq.$liveId',
      limit: 500,
    );
    return rows.length;
  }

  final draftCounts = <Map<String, dynamic>>[];
  for (final d in drafts) {
    final id = d['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    draftCounts.add({
      'id': id,
      'status': d['status'],
      'items': await countItems(id),
    });
  }

  final recentCounts = <Map<String, dynamic>>[];
  for (final l in recent) {
    final id = l['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    recentCounts.add({
      'id': id,
      'status': l['status'],
      'is_active': l['is_active'],
      'title': l['title'],
      'items': await countItems(id),
      'created_at': l['created_at'],
    });
  }

  final out = {
    'products_available_for_live_true': on.length,
    'products_available_for_live_false': off.length,
    'on_sample': on
        .take(15)
        .map((e) => {'id': e['id'], 'title': e['title'], 'ref': e['ref_code']})
        .toList(),
    'drafts': draftCounts,
    'recent_lives': recentCounts,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
  Directory('tool/reports/battery_hub_h_2026-08-23/bd').createSync(recursive: true);
  File('tool/reports/battery_hub_h_2026-08-23/bd/catalog_diag.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
}
