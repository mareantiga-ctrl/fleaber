// ignore_for_file: avoid_print
/// Corre todos os cenários BD isolados de stock/cross-pool num único processo (sem overhead de N invocações).
///
/// Uso: dart run tool/stock_lifecycle_bd_batch.dart
library;

import 'dart:io';

import 'live_ops_staging_client.dart';
import 'regression/integration_scenarios.dart';
import 'regression/staging_guard.dart';

const _scenarios = [
  ('cross_pool_rr1', 'A340'),
  ('blocked_qty', 'A341'),
  ('cross_reserved', 'A342'),
  ('gravado_sold', 'A343'),
  ('marketplace_bridge', 'A349'),
  ('cross_pool_sold_dedup', 'A344'),
  ('a3_r32_qty_alignment', 'T04'),
];

Future<void> main(List<String> args) async {
  Map<String, String> env;
  try {
    env = loadLiveOpsStagingEnv();
  } catch (e) {
    print('SKIP_CONFIG: $e');
    exit(3);
  }

  final guard = RegressionStagingGuard.check(env);
  if (!guard.ok) {
    print('SKIP_CONFIG: ${guard.reason}');
    exit(3);
  }

  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final scenarios = IntegrationScenarios(client, env);
  var fail = 0;
  final results = <String, String>{};

  print('=== STOCK LIFECYCLE BD BATCH (${_scenarios.length} cenários) ===');
  for (final (name, id) in _scenarios) {
    stdout.write('  $id $name ... ');
    final ok = await scenarios.run(name);
    results['$id:$name'] = ok ? 'PASS' : 'FAIL';
    print(ok ? 'PASS' : 'FAIL');
    if (!ok) fail++;
  }

  print('');
  print('=== RESUMO BD BATCH ===');
  for (final e in results.entries) {
    print('  ${e.key} => ${e.value}');
  }
  print('FAIL=$fail/${_scenarios.length}');

  exit(fail > 0 ? 1 : 0);
}
