// ignore_for_file: avoid_print
/// APP-065 — marca um conjunto pago do buyer de teste como enviado (prep Maestro).
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

  final orders = await sb.select(
    'orders',
    filter: 'buyer_id=eq.$buyer&bundle_id=not.is.null&status=eq.pago&order=created_at.desc',
    limit: 40,
  );

  final byBundle = <String, List<Map<String, dynamic>>>{};
  for (final o in orders) {
    final bid = o['bundle_id']?.toString() ?? '';
    if (bid.isEmpty) continue;
    byBundle.putIfAbsent(bid, () => []).add(o);
  }

  MapEntry<String, List<Map<String, dynamic>>>? target;
  for (final e in byBundle.entries) {
    if (e.value.length >= 2) {
      target = e;
      break;
    }
  }
  if (target == null) {
    stderr.writeln('no paid bundle with >=2 lines');
    exit(2);
  }

  final patched = <String>[];
  for (final o in target.value) {
    final id = o['id'].toString();
    await sb.patch('orders', 'id=eq.$id', {'status': 'enviado'});
    patched.add(id);
  }

  final after = await sb.select(
    'orders',
    filter: 'bundle_id=eq.${target.key}',
    limit: 10,
  );

  final out = {
    'bundle_id': target.key,
    'patched_order_ids': patched,
    'statuses_after': after.map((o) => {
          'id': o['id'],
          'status': o['status'],
        }).toList(),
    'expected_ui': 'Artigo Enviado',
  };

  final dir = Directory('tool/reports/battery_fail_2026-08-23/bd');
  await dir.create(recursive: true);
  await File('${dir.path}/app065_seed_enviado.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
}
