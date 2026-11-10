// ignore_for_file: avoid_print
import 'dart:io';

import 'adapter_executor.dart';
import 'models.dart';
import 'run_session.dart';

/// Executa pipelines híbridos (bot + maestro + integration).
class HybridRunner {
  HybridRunner(this.repoRoot, this.session, this.executor);

  final String repoRoot;
  final RegressionRunSession session;
  final AdapterExecutor executor;

  Future<TestRunResult> run(ManifestTest test, RegressionAdapter adapter) async {
    final sw = Stopwatch()..start();
    final layers = <String>[];
    String? lastError;

    if (adapter.requiresGuided && !session.guided) {
      sw.stop();
      return TestRunResult(
        id: test.id,
        name: test.title,
        status: 'blocked',
        layersRun: const ['hybrid'],
        durationMs: sw.elapsedMilliseconds,
        message: 'Requer --guided para híbrido ${adapter.entry}',
      );
    }

    for (final step in adapter.steps) {
      final stepTest = ManifestTest(
        id: test.id,
        title: test.title,
        area: test.area,
        priority: test.priority,
        layer: step.type,
        status: 'automated',
        adapter: _adapterForStep(step),
      );

      final result = await executor.run(stepTest);
      layers.addAll(result.layersRun);
      if (result.status == 'skip_config_missing' || result.status == 'blocked') {
        sw.stop();
        return TestRunResult(
          id: test.id,
          name: test.title,
          status: result.status,
          layersRun: layers,
          durationMs: sw.elapsedMilliseconds,
          message: 'Híbrido parado no step ${step.type}: ${result.message}',
        );
      }
      if (result.status == 'fail') {
        sw.stop();
        return TestRunResult(
          id: test.id,
          name: test.title,
          status: 'fail',
          layersRun: layers,
          durationMs: sw.elapsedMilliseconds,
          message: 'Híbrido falhou no step ${step.type}: ${result.message}',
        );
      }
      lastError = result.message;
    }

    sw.stop();
    return TestRunResult(
      id: test.id,
      name: test.title,
      status: 'pass',
      layersRun: layers,
      durationMs: sw.elapsedMilliseconds,
      message: lastError,
    );
  }

  RegressionAdapter _adapterForStep(HybridStep step) {
    switch (step.type) {
      case 'bot':
        return RegressionAdapter(
          type: 'bot',
          path: 'tool/fleaber_bot_simulator.dart',
          entry: step.scenario,
          args: const ['--bots', '10', '--duration', '30s', '--cleanup'],
          requiresLiveId: true,
          requiresStaging: true,
        );
      case 'maestro':
        return RegressionAdapter(
          type: 'maestro',
          path: '.maestro/flows/${step.flow}',
          entry: step.flow,
          requiresMaestro: true,
          requiresStaging: true,
          requiresGuided: true,
        );
      case 'integration':
        return RegressionAdapter(
          type: 'integration',
          path: 'tool/regression_integration.dart',
          entry: step.scenario,
          requiresStaging: true,
        );
      default:
        return RegressionAdapter(type: 'stub', path: step.path ?? '');
    }
  }
}
