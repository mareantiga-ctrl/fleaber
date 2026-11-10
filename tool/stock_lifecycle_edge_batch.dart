// ignore_for_file: avoid_print
library;

import 'dart:io';

import 'live_ops_staging_client.dart';
import 'regression/integration_scenarios.dart';
import 'regression/staging_guard.dart';

const _scenarios = [
  ('waitlist_stock_zero', 'A150'),
  ('partial_multi_qty_accept', 'A142'),
  ('seller_reject_pending', 'A082'),
  ('overstock_qty_confirm', 'A127'),
];

Future<void> main(List<String> args) async {
  final env = loadLiveOpsStagingEnv();
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
  print('=== EDGE BD BATCH (${_scenarios.length}) ===');
  for (final (name, id) in _scenarios) {
    stdout.write('  $id $name ... ');
    final ok = await scenarios.run(name);
    print(ok ? 'PASS' : 'FAIL');
    if (!ok) fail++;
  }
  exit(fail > 0 ? 1 : 0);
}
