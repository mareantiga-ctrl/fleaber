// ignore_for_file: avoid_print
/// Cria/garante FX1 + FX2 liveable no seller staging (E2E Face).
/// dart run tool/ps_e2e_ensure_fx_catalog.dart
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
  const sellerId = '980f4fa1-0004-42f9-abca-69f1a9c29588';

  final wanted = <Map<String, dynamic>>[
    {
      'ref_code': 'FX1',
      'title': 'Camisola Nike Azul M',
      'price': 12.0,
      'quantity': 5,
    },
    {
      'ref_code': 'FX2',
      'title': 'Camisola Nike Azul L',
      'price': 12.0,
      'quantity': 5,
    },
  ];

  final existing = await sb.select(
    'products',
    filter: 'seller_id=eq.$sellerId&ref_code=in.(FX1,FX2)',
    limit: 10,
  );
  final byRef = <String, Map<String, dynamic>>{};
  for (final p in existing) {
    byRef['${p['ref_code']}'] = p;
  }

  final out = <String, dynamic>{
    'at': DateTime.now().toUtc().toIso8601String(),
    'seller_id': sellerId,
    'items': <Map<String, dynamic>>[],
  };

  for (final w in wanted) {
    final ref = w['ref_code'] as String;
    if (byRef.containsKey(ref)) {
      final id = byRef[ref]!['id'];
      await sb.patch(
        'products',
        'id=eq.$id',
        {
          'available_for_live': true,
          'is_sold': false,
          'quantity': w['quantity'],
          'title': w['title'],
          'price': w['price'],
        },
      );
      final refreshed = await sb.select(
        'products',
        filter: 'id=eq.$id',
        limit: 1,
      );
      out['items'].add({
        'action': 'updated',
        'ref_code': ref,
        'id': id,
        'row': refreshed.isEmpty ? byRef[ref] : refreshed.first,
      });
    } else {
      final inserted = await sb.insert('products', {
        'seller_id': sellerId,
        'title': w['title'],
        'price': w['price'],
        'ref_code': ref,
        'quantity': w['quantity'],
        'available_for_live': true,
        'is_sold': false,
        'list_on_marketplace': true,
        'state': 'Bom',
        'category': 'Roupa',
      });
      out['items'].add({
        'action': 'inserted',
        'ref_code': ref,
        'row': inserted,
      });
    }
  }

  final path =
      'tool/reports/battery_ps_face_real_BRIEFING_AUDITOR/provas/E2E_FX_CATALOG.json';
  File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print(const JsonEncoder.withIndent('  ').convert(out));
  print('\nEscrito: $path');
}
