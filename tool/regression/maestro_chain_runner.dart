// ignore_for_file: avoid_print
import 'dart:io';

import 'adapter_executor.dart';
import 'maestro_execution_plans.dart';
import 'maestro_live_log.dart';
import 'models.dart';
import 'run_session.dart';
import 'maestro_device.dart';

/// Executa cadeias Maestro com sessão partilhada e fan-out de resultados.
class MaestroChainRunner {
  MaestroChainRunner({
    required this.repoRoot,
    required this.session,
    required this.executor,
    required this.manifest,
  });

  final String repoRoot;
  final RegressionRunSession session;
  final AdapterExecutor executor;
  final Map<String, ManifestTest> manifest;

  bool _sellerLoggedIn = false;
  bool _buyerLoggedIn = false;

  Future<Map<String, TestRunResult>> run(Set<String> selectedMaestroIds) async {
    final plans = MaestroExecutionPlans.build(
      selectedIds: selectedMaestroIds,
      manifest: manifest,
    );
    final results = <String, TestRunResult>{};

    print('');
    print('Maestro chains: ${plans.length} cadeia(s), '
        '${selectedMaestroIds.length} teste(s) UI');
    print('(progresso em tempo real — cada linha [HH:MM:SS] mostra o passo Maestro)');
    for (final plan in plans) {
      print('  • ${plan.id} — ${plan.description}');
    }
    print('---');

    for (final plan in plans) {
      await _runPlan(plan, results);
    }

    for (final id in selectedMaestroIds) {
      results.putIfAbsent(
        id,
        () => TestRunResult(
          id: id,
          name: manifest[id]?.title ?? id,
          status: 'blocked',
          layersRun: const ['maestro'],
          message: 'Maestro chain: sem resultado atribuído',
        ),
      );
    }

    return results;
  }

  Future<void> _runPlan(
    MaestroChainPlan plan,
    Map<String, TestRunResult> results,
  ) async {
    print('');
    MaestroLiveLog.chainStart(plan.id, plan.description);
  var chainAborted = false;

    for (var i = 0; i < plan.steps.length; i++) {
      final step = plan.steps[i];
      if (chainAborted) {
        _blockStep(step, results, plan.id);
        continue;
      }

      final device = _deviceForRole(plan.deviceRole);
      if (device == null || device.isEmpty) {
        _blockStep(step, results, 'device ${plan.deviceRole} offline');
        chainAborted = true;
        continue;
      }

      if (step.login != MaestroChainLogin.none) {
        final loginOk = await _runLogin(step.login, device, plan.driverPort);
        if (!loginOk) {
          _failStep(
            step,
            results,
            'login falhou (${step.label})',
          );
          if (step.onFail == MaestroChainOnFail.abortChain) {
            chainAborted = true;
            _blockRemaining(plan, i + 1, results, plan.id);
          }
          continue;
        }
      }

      if (step.flowPath == null && step.testIds.isEmpty) {
        continue;
      }

      if (step.testIds.isEmpty && step.flowPath != null) {
        MaestroLiveLog.nav(step.label);
        final sw = Stopwatch()..start();
        final proc = await executor.invokeMaestroFlow(
          flowPath: _abs(step.flowPath!),
          device: device,
          driverPort: plan.driverPort,
          skipInstall: true,
          streamOutput: true,
        );
        sw.stop();
        if (proc.exitCode != 0) {
          final reason = MaestroLiveLog.parseFailure(
            proc.stdout.toString(),
            proc.stderr.toString(),
          );
          MaestroLiveLog.testEnd(
            testIds: const [],
            ok: false,
            durationMs: sw.elapsedMilliseconds,
            reason: reason.isEmpty ? 'exit=${proc.exitCode}' : reason,
          );
          if (step.onFail == MaestroChainOnFail.abortChain) {
            chainAborted = true;
            _blockRemaining(plan, i + 1, results, plan.id);
          }
        }
        continue;
      }

      if (step.kind == MaestroChainStepKind.isolated) {
        for (final id in step.testIds) {
          final test = manifest[id];
          if (test == null) continue;
          final sw = Stopwatch()..start();
          final result = await executor.run(test);
          sw.stop();
          results[id] = TestRunResult(
            id: result.id,
            name: result.name,
            status: result.status,
            layersRun: [
              ...result.layersRun,
              'maestro_chain:${plan.id}',
            ],
            durationMs: result.durationMs,
            message: result.message != null
                ? 'chain:${plan.id} ${result.message}'
                : 'chain:${plan.id}',
          );
          print('  ${result.id} ${result.status} (isolated)');
          if (result.status != 'pass' &&
              step.onFail == MaestroChainOnFail.abortChain) {
            chainAborted = true;
            _blockRemaining(plan, i + 1, results, plan.id);
            break;
          }
        }
        continue;
      }

      for (final id in step.testIds) {
        final test = manifest[id];
        if (test == null) continue;
        for (final hook in step.setupHooks) {
          await Process.run(
            'dart',
            ['run', 'tool/$hook.dart'],
            workingDirectory: repoRoot,
            runInShell: Platform.isWindows,
          );
        }
        await executor.runMaestroPreHooks(test);
      }

      final stepTitle = step.testIds
          .map((id) => manifest[id]?.title ?? id)
          .join(' | ');
      MaestroLiveLog.testStart(
        testIds: step.testIds,
        title: stepTitle.isEmpty ? step.label : stepTitle,
        device: device,
        flowPath: step.flowPath ?? step.label,
        chainId: plan.id,
      );

      if (step.adbDeepLink != null && step.adbDeepLink!.isNotEmpty) {
        final base = session.stagingEnv?['MAESTRO_DEEP_LINK_BASE']?.trim() ??
            'fleaber://fleaber.com';
        final path = step.adbDeepLink!.startsWith('/')
            ? step.adbDeepLink!
            : '/${step.adbDeepLink!}';
        final link = '$base$path';
        MaestroLiveLog.adbDeepLink(link, device);
        final okLink = await MaestroDeviceProbe.openDeepLinkViaAdb(
          device: device,
          link: link,
        );
        if (!okLink) {
          final reason = 'adb deep link falhou: $link';
          for (final id in step.testIds) {
            results[id] = TestRunResult(
              id: id,
              name: manifest[id]?.title ?? id,
              status: 'fail',
              layersRun: ['maestro', 'maestro_chain:${plan.id}'],
              message: reason,
            );
          }
          MaestroLiveLog.testEnd(
            testIds: step.testIds,
            ok: false,
            durationMs: 0,
            reason: reason,
          );
          if (step.onFail == MaestroChainOnFail.abortChain) {
            chainAborted = true;
            _blockRemaining(plan, i + 1, results, plan.id);
          }
          continue;
        }
      }

      final sw = Stopwatch()..start();
      final proc = await executor.invokeMaestroFlow(
        flowPath: _abs(step.flowPath!),
        device: device,
        driverPort: plan.driverPort,
        skipInstall: true,
        streamOutput: true,
      );
      sw.stop();

      final ok = proc.exitCode == 0;
      final perTestMs = step.testIds.isEmpty
          ? sw.elapsedMilliseconds
          : (sw.elapsedMilliseconds / step.testIds.length).round();
      final failReason = ok
          ? null
          : MaestroLiveLog.parseFailure(
              proc.stdout.toString(),
              proc.stderr.toString(),
            );

      for (final id in step.testIds) {
        final test = manifest[id]!;
        results[id] = TestRunResult(
          id: id,
          name: test.title,
          status: ok ? 'pass' : 'fail',
          layersRun: ['maestro', 'maestro_chain:${plan.id}'],
          durationMs: perTestMs,
          message: ok
              ? 'chain:${plan.id}/${step.label}'
              : 'chain:${plan.id}/${step.label}: $failReason',
        );
      }
      MaestroLiveLog.testEnd(
        testIds: step.testIds,
        ok: ok,
        durationMs: sw.elapsedMilliseconds,
        reason: failReason,
      );

      if (!ok && step.onFail == MaestroChainOnFail.abortChain) {
        chainAborted = true;
        _blockRemaining(plan, i + 1, results, plan.id);
      }
    }

    MaestroLiveLog.chainEnd(plan.id, aborted: chainAborted);
  }

  Future<bool> _runLogin(
    MaestroChainLogin login,
    String device,
    int port,
  ) async {
    final String flow;
    switch (login) {
      case MaestroChainLogin.sellerCold:
        flow = _sellerLoggedIn
            ? '.maestro/subflows/login_seller_warm.yaml'
            : '.maestro/subflows/login_seller.yaml';
        break;
      case MaestroChainLogin.sellerWarm:
        flow = _sellerLoggedIn
            ? '.maestro/subflows/login_seller_warm.yaml'
            : '.maestro/subflows/login_seller.yaml';
        break;
      case MaestroChainLogin.buyerCold:
      case MaestroChainLogin.buyerWarm:
        flow = _buyerLoggedIn
            ? '.maestro/subflows/login_buyer_warm.yaml'
            : '.maestro/subflows/login_buyer.yaml';
        break;
      case MaestroChainLogin.none:
        return true;
    }

    MaestroLiveLog.login(flow);
    final proc = await executor.invokeMaestroFlow(
      flowPath: _abs(flow),
      device: device,
      driverPort: port,
      skipInstall: true,
      streamOutput: true,
    );
    if (proc.exitCode != 0) return false;

    switch (login) {
      case MaestroChainLogin.sellerCold:
      case MaestroChainLogin.sellerWarm:
        _sellerLoggedIn = true;
      case MaestroChainLogin.buyerCold:
      case MaestroChainLogin.buyerWarm:
        _buyerLoggedIn = true;
      case MaestroChainLogin.none:
        break;
    }
    return true;
  }

  String? _deviceForRole(String role) {
    final env = session.stagingEnv ?? {};
    if (role == 'buyer') {
      return env['MAESTRO_DEVICE_BUYER']?.trim() ??
          session.maestroProbe?.defaultDevice;
    }
    return env['MAESTRO_DEVICE_SELLER']?.trim() ??
        env['MAESTRO_DEVICE_DEFAULT']?.trim() ??
        session.maestroProbe?.defaultDevice;
  }

  String _abs(String rel) {
    final norm = rel.replaceAll('/', Platform.pathSeparator);
    if (norm.startsWith('.maestro')) {
      return '$repoRoot${Platform.pathSeparator}$norm';
    }
    return norm;
  }

  void _blockRemaining(
    MaestroChainPlan plan,
    int fromStep,
    Map<String, TestRunResult> results,
    String reason,
  ) {
    for (var i = fromStep; i < plan.steps.length; i++) {
      _blockStep(plan.steps[i], results, reason);
    }
  }

  void _blockStep(
    MaestroChainStep step,
    Map<String, TestRunResult> results,
    String reason,
  ) {
    for (final id in step.testIds) {
      if (results.containsKey(id)) continue;
      results[id] = TestRunResult(
        id: id,
        name: manifest[id]?.title ?? id,
        status: 'blocked',
        layersRun: const ['maestro'],
        message: 'Chain abortada: $reason',
      );
    }
  }

  void _failStep(
    MaestroChainStep step,
    Map<String, TestRunResult> results,
    String message,
  ) {
    for (final id in step.testIds) {
      results[id] = TestRunResult(
        id: id,
        name: manifest[id]?.title ?? id,
        status: 'fail',
        layersRun: const ['maestro'],
        message: message,
      );
    }
  }
}
