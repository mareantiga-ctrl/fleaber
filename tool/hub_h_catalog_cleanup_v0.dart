// ignore_for_file: avoid_print
/// Desliga available_for_live em lixo V0/QA do seller de testes; termina live activa.
/// Mantém C27 A/B e o que o vendedor ligar de propósito no prep.
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

  const sellerId = '980f4fa1-0004-42f9-abca-69f1a9c29588';

  final on = await client.select(
    'products',
    filter: 'seller_id=eq.$sellerId&available_for_live=eq.true&is_sold=eq.false',
    limit: 500,
  );

  var turnedOff = 0;
  var kept = 0;
  final keptTitles = <String>[];
  for (final p in on) {
    final id = p['id']?.toString() ?? '';
    final title = (p['title']?.toString() ?? '').trim();
    final ref = (p['ref_code']?.toString() ?? '').trim().toUpperCase();
    final isC27 = title.toUpperCase().contains('C27') || ref.startsWith('C27');
    final isJunk = title.toUpperCase().startsWith('V0') ||
        ref.startsWith('V0TEST') ||
        title.toUpperCase().contains('REGRESSION') ||
        ref.startsWith('C6');
    if (isC27) {
      kept++;
      keptTitles.add('$title ($ref)');
      continue;
    }
    if (!isJunk && !isC27) {
      // Outros ON: desligar também para o prep ficar limpo; vendedor volta a ligar 1.
      // (QA staging — não é produção.)
    }
    if (id.isEmpty) continue;
    await client.patch('products', 'id=eq.$id', {'available_for_live': false});
    turnedOff++;
  }

  final lives = await client.select(
    'lives',
    filter:
        'or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&is_active=eq.true',
    limit: 10,
  );
  var ended = 0;
  for (final l in lives) {
    final id = l['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    await client.patch('lives', 'id=eq.$id', {
      'status': 'ended',
      'is_active': false,
    });
    ended++;
  }

  final after = await client.select(
    'products',
    filter: 'seller_id=eq.$sellerId&available_for_live=eq.true&is_sold=eq.false',
    limit: 50,
  );

  final out = {
    'turned_off': turnedOff,
    'kept_c27_count': kept,
    'kept_c27': keptTitles,
    'lives_ended': ended,
    'still_on': after
        .map((e) => {'title': e['title'], 'ref': e['ref_code']})
        .toList(),
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
  Directory('tool/reports/battery_hub_h_2026-08-23/bd').createSync(recursive: true);
  File('tool/reports/battery_hub_h_2026-08-23/bd/catalog_cleanup_v0.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
}
