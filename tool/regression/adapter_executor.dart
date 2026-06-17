// ignore_for_file: avoid_print
import 'dart:io';

import 'hybrid_runner.dart';
import 'maestro_device.dart';
import 'maestro_live_log.dart';
import 'models.dart';
import 'run_session.dart';

class AdapterExecutor {
  AdapterExecutor(this.repoRoot, {RegressionRunSession? session})
      : session = session ?? RegressionRunSession(guided: false) {
    _hybrid = HybridRunner(repoRoot, this.session, this);
  }

  final String repoRoot;
  final RegressionRunSession session;
  late final HybridRunner _hybrid;

  Future<TestRunResult> run(ManifestTest test) async {
    final sw = Stopwatch()..start();
    final adapter = test.adapter;

    if (adapter == null) {
      if (test.status == 'manual' || test.layer == 'manual') {
        sw.stop();
        return TestRunResult(
          id: test.id,
          name: test.title,
          status: 'manual',
          durationMs: sw.elapsedMilliseconds,
          message: 'Requer validação manual — ver ${test.sourceDoc}',
        );
      }
      sw.stop();
      return TestRunResult(
        id: test.id,
        name: test.title,
        status: 'not_implemented',
        durationMs: sw.elapsedMilliseconds,
        message: 'Sem adapter (${test.layer})',
      );
    }

    final pre = _precheck(adapter);
    if (pre != null) {
      sw.stop();
      return TestRunResult(
        id: test.id,
        name: test.title,
        status: pre.status,
        layersRun: pre.layers,
        durationMs: sw.elapsedMilliseconds,
        message: pre.message,
      );
    }

    switch (adapter.type) {
      case 'unit':
        return _runUnit(test, adapter, sw);
      case 'integration':
        return _runIntegration(test, adapter, sw);
      case 'bot':
        return _runBot(test, adapter, sw);
      case 'maestro':
        return _runMaestro(test, adapter, sw);
      case 'hybrid':
        return _hybrid.run(test, adapter);
      case 'manual_checkpoint':
        sw.stop();
        return TestRunResult(
          id: test.id,
          name: test.title,
          status: 'manual',
          layersRun: const ['manual'],
          durationMs: sw.elapsedMilliseconds,
          message: adapter.entry ?? 'Checkpoint manual — ver ${adapter.path}',
        );
      case 'guided_checkpoint':
        return _runGuidedCheckpoint(test, adapter, sw);
      default:
        sw.stop();
        return TestRunResult(
          id: test.id,
          name: test.title,
          status: 'skip_config_missing',
          durationMs: sw.elapsedMilliseconds,
          message: 'Tipo adapter desconhecido: ${adapter.type}',
        );
    }
  }

  _PrecheckResult? _precheck(RegressionAdapter adapter) {
    if (adapter.type == 'manual_checkpoint') return null;
    if (adapter.type == 'guided_checkpoint') {
      if (!session.guided) {
        return _PrecheckResult('blocked', const ['guided'], 'Requer --guided');
      }
      return null;
    }
    if (adapter.requiresStaging && !session.stagingOk) {
      return _PrecheckResult(
        'skip_config_missing',
        ['precheck'],
        session.stagingCheck?.reason ?? 'staging não disponível',
      );
    }
    if (adapter.type == 'maestro' || adapter.requiresMaestro) {
      if (!_maestroReady()) {
        return _PrecheckResult(
          'skip_config_missing',
          ['precheck'],
          session.maestroProbe?.skipReason ??
              'Maestro/device em falta — liga emulador ou .maestro/.env',
        );
      }
    }
    if (adapter.requiresGuided && !session.guided) {
      if (adapter.type == 'hybrid' || adapter.type == 'guided_checkpoint') {
        return _PrecheckResult(
          'blocked',
          ['precheck'],
          'Requer --guided (híbrido/checkpoint UI real)',
        );
      }
    }
    return null;
  }

  bool _maestroReady() {
    final probe = session.maestroProbe;
    if (probe != null) return probe.canRunMaestro;
    final bat = '$repoRoot/.tools/maestro/maestro/bin/maestro.bat';
    if (!File(bat).existsSync()) return false;
    return File('$repoRoot/.maestro/.env').existsSync();
  }

  Future<TestRunResult> _runUnit(
    ManifestTest test,
    RegressionAdapter adapter,
    Stopwatch sw,
  ) async {
    final testPath = '$repoRoot/${adapter.path}';
    if (!File(testPath).existsSync()) {
      sw.stop();
      return TestRunResult(
        id: test.id,
        name: test.title,
        status: 'fail',
        layersRun: const ['unit'],
        durationMs: sw.elapsedMilliseconds,
        message: 'Ficheiro unit em falta: ${adapter.path}',
      );
    }

    final flutter = Platform.isWindows ? 'flutter.bat' : 'flutter';
    final cmd = <String>['test', adapter.path];
    if (adapter.entry != null && adapter.entry!.isNotEmpty) {
      cmd.addAll(['--name', adapter.entry!]);
    }

    final result = await Process.run(
      flutter,
      cmd,
      workingDirectory: repoRoot,
      runInShell: Platform.isWindows,
    );
    sw.stop();

    final ok = result.exitCode == 0;
    final stderr = result.stderr.toString().trim();
    final stdout = result.stdout.toString().trim();
    final tail = stderr.isNotEmpty ? stderr : stdout;
    final msg = ok
        ? null
        : (tail.length > 400 ? tail.substring(tail.length - 400) : tail);

    return TestRunResult(
      id: test.id,
      name: test.title,
      status: ok ? 'pass' : 'fail',
      layersRun: const ['unit'],
      durationMs: sw.elapsedMilliseconds,
      message: msg,
    );
  }

  Future<TestRunResult> _runIntegration(
    ManifestTest test,
    RegressionAdapter adapter,
    Stopwatch sw,
  ) async {
    final scenario = adapter.entry ?? '';
    final result = await Process.run(
      'dart',
      [
        'run',
        'tool/regression_integration.dart',
        '--scenario',
        scenario,
        '--test-id',
        test.id,
      ],
      workingDirectory: repoRoot,
      runInShell: Platform.isWindows,
    );
    sw.stop();

    if (result.exitCode == 3) {
      return TestRunResult(
        id: test.id,
        name: test.title,
        status: 'skip_config_missing',
        layersRun: const ['integration'],
        durationMs: sw.elapsedMilliseconds,
        message: result.stdout.toString().trim(),
      );
    }

    final ok = result.exitCode == 0;
    return TestRunResult(
      id: test.id,
      name: test.title,
      status: ok ? 'pass' : 'fail',
      layersRun: const ['integration'],
      durationMs: sw.elapsedMilliseconds,
      message: ok ? null : _tailOutput(result),
    );
  }

  Future<TestRunResult> _runBot(
    ManifestTest test,
    RegressionAdapter adapter,
    Stopwatch sw,
  ) async {
    final liveId = await session.guidedSession.ensureLiveId(
      fromEnv: session.liveIdFromEnv,
    );
    if (liveId == null || liveId.isEmpty) {
      sw.stop();
      return TestRunResult(
        id: test.id,
        name: test.title,
        status: 'skip_config_missing',
        layersRun: const ['bot'],
        durationMs: sw.elapsedMilliseconds,
        message: 'live_id em falta — define LIVE_OPS_TEST_LIVE_ID ou usa --guided',
      );
    }

    final args = <String>[
      'run',
      'tool/fleaber_bot_simulator.dart',
      '--live-id',
      liveId,
      '--scenario',
      adapter.entry ?? 'full',
      '--i-know-this-is-staging',
      ...adapter.args,
    ];

    final result = await Process.run(
      'dart',
      args,
      workingDirectory: repoRoot,
      runInShell: Platform.isWindows,
    );
    sw.stop();

    final ok = result.exitCode == 0;
    return TestRunResult(
      id: test.id,
      name: test.title,
      status: ok ? 'pass' : 'fail',
      layersRun: const ['bot'],
      durationMs: sw.elapsedMilliseconds,
      message: ok ? 'bot:${adapter.entry} live=$liveId' : _tailOutput(result),
    );
  }

  Future<TestRunResult> _runGuidedCheckpoint(
    ManifestTest test,
    RegressionAdapter adapter,
    Stopwatch sw,
  ) async {
    if (!session.guided) {
      sw.stop();
      return TestRunResult(
        id: test.id,
        name: test.title,
        status: 'blocked',
        layersRun: const ['guided'],
        durationMs: sw.elapsedMilliseconds,
        message: adapter.entry ?? 'Requer --guided',
      );
    }

    print('');
    print('┌─ GUIDED ${test.id} ─────────────────────────────');
    print('│ ${adapter.entry ?? test.title}');
    print('│ ENTER=pass | fail=falhou | skip=saltou');
    print('└──────────────────────────────────────────────');
    stdout.write('resultado> ');
    final line = stdin.readLineSync()?.trim().toLowerCase() ?? '';
    sw.stop();

    final status = switch (line) {
      'pass' || 'p' || '' => 'pass',
      'fail' || 'f' => 'fail',
      'skip' || 's' => 'skip_config_missing',
      _ => 'blocked',
    };

    return TestRunResult(
      id: test.id,
      name: test.title,
      status: status,
      layersRun: const ['guided'],
      durationMs: sw.elapsedMilliseconds,
      message: 'guided: $line',
    );
  }

  Future<TestRunResult> _runMaestro(
    ManifestTest test,
    RegressionAdapter adapter,
    Stopwatch sw,
  ) async {
    if (session.guided) {
      final flow = (adapter.entry ?? '').toLowerCase();
      final area = test.area;
      if (area == 'publish' ||
          flow.contains('seller') ||
          flow.contains('studio') ||
          flow.contains('preparar')) {
        final ok = await session.guidedSession.confirmSellerStudio();
        if (!ok) {
          sw.stop();
          return TestRunResult(
            id: test.id,
            name: test.title,
            status: 'skip_config_missing',
            layersRun: const ['maestro'],
            durationMs: sw.elapsedMilliseconds,
            message: 'Guided: studio vendedor não confirmado',
          );
        }
      } else if (area == 'buyer_player' ||
          area == 'checkout' ||
          area == 'raffle' ||
          flow.contains('buyer') ||
          flow.contains('bag') ||
          flow.contains('player')) {
        final ok = await session.guidedSession.confirmBuyerPlayer();
        if (!ok) {
          sw.stop();
          return TestRunResult(
            id: test.id,
            name: test.title,
            status: 'skip_config_missing',
            layersRun: const ['maestro'],
            durationMs: sw.elapsedMilliseconds,
            message: 'Guided: player comprador não confirmado',
          );
        }
      }
    }

    await _runMaestroPreHooks(test);

    final flowPath = adapter.path.startsWith('../')
        ? '$repoRoot/.maestro/${adapter.path.replaceFirst('../', '')}'
        : adapter.path.startsWith('.maestro')
            ? '$repoRoot/${adapter.path}'
            : '$repoRoot/.maestro/flows/${adapter.path}';

    final freshProbe = await MaestroDeviceProbe.detect(repoRoot);
    var device = _maestroDeviceForFlow(adapter);
    if (device != null &&
        freshProbe.devices.isNotEmpty &&
        !freshProbe.devices.contains(device)) {
      device = freshProbe.devices.first;
      print('AVISO Maestro: device pedido offline — a usar $device');
    }
    if ((device == null || device.isEmpty) && freshProbe.devices.isNotEmpty) {
      device = freshProbe.devices.first;
    }
    if (!freshProbe.canRunMaestro) {
      sw.stop();
      return TestRunResult(
        id: test.id,
        name: test.title,
        status: 'skip_config_missing',
        layersRun: const ['maestro'],
        durationMs: sw.elapsedMilliseconds,
        message: freshProbe.skipReason.isNotEmpty
            ? freshProbe.skipReason
            : 'Maestro/device em falta — liga emulador ou APK',
      );
    }

    final driverPort = _maestroDriverPortForFlow(adapter);
    final flowKey = (adapter.entry ?? adapter.path).toLowerCase();
    final isSellerHarness = flowKey.contains('harness_assert') ||
        flowKey.contains('harness_accept') ||
        flowKey.contains('seller_harness');
    final isHelperLink = flowKey.contains('helper_link');

    ProcessResult result;
    if (isSellerHarness && device != null && device.isNotEmpty) {
      result = await _runSellerHarnessMaestro(
        device: device,
        driverPort: driverPort,
        test: test,
        adapter: adapter,
      );
    } else if (isHelperLink && device != null && device.isNotEmpty) {
      result = await _runHelperLinkWithOperatorPause(
        device: device,
        driverPort: driverPort,
      );
      if (result.exitCode == -99) {
        sw.stop();
        return TestRunResult(
          id: test.id,
          name: test.title,
          status: 'blocked',
          layersRun: const ['maestro', 'guided'],
          durationMs: sw.elapsedMilliseconds,
          message: 'Pausa A387: operador não confirmou ecrã convite inválido',
        );
      }
    } else {
      final adbPlan = _maestroAdbDeepLinkPlan(adapter);
      if (adbPlan != null && device != null && device.isNotEmpty) {
        result = await _invokeMaestroFlow(
          flowPath: flowPath,
          device: device,
          driverPort: driverPort,
        );
      } else {
        result = await _invokeMaestroFlow(
          flowPath: flowPath,
          device: device,
          driverPort: driverPort,
        );
      }
    }
    sw.stop();

    return _maestroResultFromProcess(
      test: test,
      adapter: adapter,
      sw: sw,
      result: result,
    );
  }

  /// Hooks Dart antes de um passo Maestro (BD, seed harness, etc.).
  Future<void> runMaestroPreHooks(ManifestTest test) async {
    await _runMaestroPreHooks(test);
  }

  Future<void> _runMaestroPreHooks(ManifestTest test) async {
    final adapter = test.adapter;
    if (adapter == null) return;
    if (adapter.type != 'maestro' && !adapter.requiresMaestro) return;

    final flow = (adapter.entry ?? adapter.path).toLowerCase();
    if (flow.contains('harness_assert') ||
        flow.contains('seller_harness') ||
        flow.contains('harness_accept')) {
      final mode = switch (test.id) {
        'A090' => 'accepted',
        'A094' => 'cancelled',
        _ => 'pending',
      };
      await Process.run(
        'dart',
        ['run', 'tool/maestro_seed_harness.dart', '--mode', mode],
        workingDirectory: repoRoot,
        runInShell: Platform.isWindows,
      );
    }
    if (test.id == 'A002') {
      await Process.run(
        'dart',
        ['run', 'tool/maestro_prep_empty_catalog.dart'],
        workingDirectory: repoRoot,
        runInShell: Platform.isWindows,
      );
    }
  }

  /// Invoca `run_maestro_flow.ps1` (usado pelas cadeias).
  Future<ProcessResult> invokeMaestroFlow({
    required String flowPath,
    String? device,
    required int driverPort,
    bool skipInstall = false,
    bool streamOutput = false,
  }) =>
      _invokeMaestroFlow(
        flowPath: flowPath,
        device: device,
        driverPort: driverPort,
        skipInstall: skipInstall,
        streamOutput: streamOutput,
      );

  String tailMaestroOutput(ProcessResult result) => _tailOutput(result);

  /// Seller harness: login → adb deep link → assert (A089/A090/A094).
  Future<ProcessResult> _runSellerHarnessMaestro({
    required String device,
    required int driverPort,
    required ManifestTest test,
    required RegressionAdapter adapter,
  }) async {
    final loginResult = await _invokeMaestroFlow(
      flowPath: '$repoRoot/.maestro/flows/v2_seller_harness_login.yaml',
      device: device,
      driverPort: driverPort,
    );
    if (loginResult.exitCode != 0) {
      return loginResult;
    }

    final env = session.stagingEnv ?? <String, String>{};
    final base = env['MAESTRO_DEEP_LINK_BASE']?.trim() ?? 'fleaber://fleaber.com';
    final liveId = env['MAESTRO_LIVE_ID']?.trim() ?? '';
    if (liveId.isEmpty) {
      return ProcessResult(1, 1, 'MAESTRO_LIVE_ID em falta', '');
    }

    var link = '$base/maestroSellerStudio?liveId=$liveId';
    final harnessQuery = switch (test.id) {
      'A089' => 'expandCategory=inBag',
      'A090' => 'expandCategory=accepted',
      'A094' => 'opsSection=payments',
      _ => '',
    };
    if (harnessQuery.isNotEmpty) {
      link = '$link&$harnessQuery';
    }

    await MaestroDeviceProbe.openDeepLinkViaAdb(device: device, link: link);
    await Future<void>.delayed(const Duration(seconds: 8));

    final assertFlow = adapter.entry ?? 'v2_seller_harness_assert_pending.yaml';
    final assertPath = assertFlow.startsWith('.maestro')
        ? '$repoRoot/$assertFlow'
        : '$repoRoot/.maestro/flows/$assertFlow';

    return _invokeMaestroFlow(
      flowPath: assertPath,
      device: device,
      driverPort: driverPort,
      skipInstall: true,
    );
  }

  /// A387: login+open convite → PAUSA (confirmar ecrã no 5558) → assert mensagem.
  Future<ProcessResult> _runHelperLinkWithOperatorPause({
    required String device,
    required int driverPort,
  }) async {
    final openResult = await _invokeMaestroFlow(
      flowPath: '$repoRoot/.maestro/flows/helper_link_open.yaml',
      device: device,
      driverPort: driverPort,
    );
    if (openResult.exitCode != 0) {
      return openResult;
    }

    // Deep link convite via adb (openLink Maestro falha em foreground).
    final base = session.stagingEnv?['MAESTRO_DEEP_LINK_BASE']?.trim() ??
        'fleaber://fleaber.com';
    await MaestroDeviceProbe.openDeepLinkViaAdb(
      device: device,
      link:
          '$base/conviteColaborador?helperLinkId=00000000-0000-0000-0000-000000000000',
    );

    print('');
    print('══════════════════════════════════════════════════');
    print('  PAUSA A387 — emulador BUYER ($device)');
    print('  Confirma que vês «Convite indisponível» no ecrã.');
    print('  Se não vires, o adb já re-disparou o deep link — espera 5s.');
    print('  ENTER=continuar | skip=saltar');
    print('══════════════════════════════════════════════════');

    final ok = await session.guidedSession.confirmHelperLinkInvalidScreen();
    if (!ok) {
      return ProcessResult(0, -99, 'operator_pause_skip', '');
    }

    return _invokeMaestroFlow(
      flowPath: '$repoRoot/.maestro/flows/helper_link_invalid_assert.yaml',
      device: device,
      driverPort: driverPort,
      skipInstall: true,
    );
  }

  Future<ProcessResult> _invokeMaestroFlow({
    String? flowPath,
    String? loginSubflow,
    String? opsFlow,
    String? device,
    required int driverPort,
    bool skipInstall = false,
    bool streamOutput = false,
  }) async {
    final path = flowPath ??
        (loginSubflow != null
            ? '$repoRoot/.maestro/$loginSubflow'
            : '$repoRoot/.maestro/$opsFlow');
    final args = [
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      'tool/run_maestro_flow.ps1',
      '-FlowPath',
      path.replaceAll('\\', '/'),
      if (device != null && device.isNotEmpty) ...[
        '-Device',
        device,
      ],
      if (driverPort > 0) ...[
        '-DriverHostPort',
        '$driverPort',
      ],
      if (skipInstall) '-SkipInstall',
    ];
    if (streamOutput) {
      return MaestroLiveLog.runStreaming(
        executable: 'powershell',
        arguments: args,
        workingDirectory: repoRoot,
        runInShell: true,
      );
    }
    return Process.run(
      'powershell',
      args,
      workingDirectory: repoRoot,
      runInShell: true,
    );
  }

  TestRunResult _maestroResultFromProcess({
    required ManifestTest test,
    required RegressionAdapter adapter,
    required Stopwatch sw,
    required ProcessResult result,
    String phase = '',
  }) {
    final out = _tailOutput(result).toLowerCase();
    if (out.contains('nao encontrado') ||
        out.contains('no devices/emulators') ||
        out.contains('not connected') ||
        out.contains('0 devices connected') ||
        out.contains('maestro nao encontrado')) {
      return TestRunResult(
        id: test.id,
        name: test.title,
        status: 'skip_config_missing',
        layersRun: const ['maestro'],
        durationMs: sw.elapsedMilliseconds,
        message: 'Maestro/device em falta — liga emulador ou APK',
      );
    }

    final ok = result.exitCode == 0;
    return TestRunResult(
      id: test.id,
      name: test.title,
      status: ok ? 'pass' : 'fail',
      layersRun: const ['maestro'],
      durationMs: sw.elapsedMilliseconds,
      message: ok
          ? adapter.entry
          : phase.isNotEmpty
              ? '[$phase] ${_tailOutput(result)}'
              : _tailOutput(result),
    );
  }

  _MaestroAdbPlan? _maestroAdbDeepLinkPlan(RegressionAdapter adapter) {
    final flow = (adapter.entry ?? adapter.path).toLowerCase();
    final env = session.stagingEnv;
    if (env == null) return null;
    final base = env['MAESTRO_DEEP_LINK_BASE']?.trim() ?? 'fleaber://fleaber.com';
    if (flow.contains('harness_accept') || flow.contains('seller_harness')) {
      final liveId = env['MAESTRO_LIVE_ID']?.trim() ?? '';
      if (liveId.isEmpty) return null;
      return _MaestroAdbPlan(
        loginSubflow: 'subflows/login_seller.yaml',
        deepLink: '$base/maestroSellerStudio?liveId=$liveId',
        opsFlow: 'flows/v2_seller_harness_ops.yaml',
      );
    }
    if (flow.contains('helper_link')) {
      return _MaestroAdbPlan(
        loginSubflow: 'subflows/login_buyer.yaml',
        deepLink:
            '$base/conviteColaborador?helperLinkId=00000000-0000-0000-0000-000000000000',
        opsFlow: 'flows/helper_link_invalid_assert.yaml',
      );
    }
    return null;
  }

  String? _maestroDeviceForFlow(RegressionAdapter adapter) {
    final flow = (adapter.entry ?? adapter.path).toLowerCase();
    final env = session.stagingEnv;
    if (flow.contains('helper_link')) {
      return env?['MAESTRO_DEVICE_BUYER']?.trim() ??
          session.maestroDeviceBuyer ??
          session.maestroProbe?.defaultDevice;
    }
    if (flow.contains('seller') ||
        flow.contains('studio') ||
        flow.contains('harness') ||
        flow.contains('preparar')) {
      return env?['MAESTRO_DEVICE_SELLER']?.trim() ??
          session.maestroProbe?.defaultDevice;
    }
    return env?['MAESTRO_DEVICE_BUYER']?.trim() ??
        session.maestroDeviceBuyer ??
        session.maestroProbe?.defaultDevice;
  }

  int _maestroDriverPortForFlow(RegressionAdapter adapter) {
    final flow = (adapter.entry ?? adapter.path).toLowerCase();
    if (flow.contains('seller') ||
        flow.contains('studio') ||
        flow.contains('harness') ||
        flow.contains('preparar')) {
      return 7001;
    }
    return 7002;
  }

  String _tailOutput(ProcessResult result) {
    final stderr = result.stderr.toString().trim();
    final stdout = result.stdout.toString().trim();
    return MaestroLiveLog.parseFailure(stdout, stderr);
  }
}

class _PrecheckResult {
  _PrecheckResult(this.status, this.layers, this.message);

  final String status;
  final List<String> layers;
  final String message;
}

class _MaestroAdbPlan {
  const _MaestroAdbPlan({
    required this.loginSubflow,
    required this.deepLink,
    required this.opsFlow,
  });

  final String loginSubflow;
  final String deepLink;
  final String opsFlow;
}
