// ignore_for_file: avoid_print
/// Integration scenarios para o regression runner (staging BD/RPC).
///
/// Uso:
///   dart run tool/regression_integration.dart --scenario reconcile
///   dart run tool/regression_integration.dart --scenario cross_pool_rr1 --test-id A340
library;

import 'dart:io';

import 'live_ops_staging_client.dart';
import 'regression/integration_scenarios.dart';
import 'regression/staging_guard.dart';

Future<void> main(List<String> args) async {
  String? scenario;
  String? testId;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--scenario' && i + 1 < args.length) {
      scenario = args[++i];
    } else if (args[i] == '--test-id' && i + 1 < args.length) {
      testId = args[++i];
    }
  }

  if (scenario == null || scenario.isEmpty) {
    print('Use: --scenario <name> [--test-id A###]');
    exit(2);
  }

  Map<String, String> env;
  try {
    env = loadLiveOpsStagingEnv();
  } catch (e) {
    print('SKIP_CONFIG: $e');
    exit(3);
  }

  final check = RegressionStagingGuard.check(env);
  if (!check.ok) {
    print('SKIP_CONFIG: ${check.reason}');
    exit(3);
  }

  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  print('Integration scenario: $scenario${testId != null ? " ($testId)" : ""}');
  print('URL: ${client.url}');

  final ok = await IntegrationScenarios(client, env).run(scenario);
  if (ok) {
    print('PASS');
    exit(0);
  } else {
    print('FAIL');
    exit(1);
  }
}
