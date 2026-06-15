// ignore_for_file: avoid_print
import 'dart:io';

import '../live_ops_staging_client.dart';
import 'adapter_auto_mapper.dart';
import 'adapter_executor.dart';
import 'adapter_registry.dart';
import 'area_mapper.dart';
import 'models.dart';
import '../maestro_seed_harness.dart';
import 'guided_session.dart';
import 'maestro_device.dart';
import 'report_writer.dart';
import 'run_session.dart';
import 'staging_guard.dart';
import 'store.dart';
import 'failure_classifier.dart';

class RegressionRunner {
  RegressionRunner(this.options)
      : paths = RegressionPaths(options.repoRoot ?? _detectRepoRoot());

  final RunnerOptions options;
  final RegressionPaths paths;
  late final RegressionStore store = RegressionStore(paths);

  static String _detectRepoRoot() {
    var dir = Directory.current;
    for (var i = 0; i < 8; i++) {
      if (File('${dir.path}/pubspec.yaml').existsSync()) {
        return dir.path;
      }
      dir = dir.parent;
    }
    return Directory.current.path;
  }

  Future<int> run() async {
    if (options.selfTest) {
      return _runSelfTest();
    }

    if (options.suggestRetestChanged != null) {
      return _suggestRetest(options.suggestRetestChanged!);
    }

    if (options.recordManual != null) {
      return _recordManual(options.recordManual!);
    }

    final manifest = store.loadManifest(regenerate: options.regenerateManifest);
    var state = store.loadState(manifest);

    final command = _commandLabel();
    final ids = TestFilter.selectIds(
      manifest: manifest,
      state: state,
      range: options.range,
      priority: options.priority,
      area: options.area,
      singleId: options.id,
      failedOnly: options.failedOnly,
      retestRequired: options.retestRequired,
    );

    if (!options.full &&
        !options.failedOnly &&
        !options.retestRequired &&
        options.range == null &&
        options.priority == null &&
        options.area == null &&
        options.id == null) {
      print('Nenhum modo seleccionado. Use --full ou um filtro (--range, --priority, ...).');
      return 2;
    }

    if (ids.isEmpty) {
      print('Nenhum teste seleccionado para o filtro actual.');
      return 1;
    }

    var stagingEnv = _tryLoadStagingEnv() ?? <String, String>{};
    final stagingCheck = RegressionStagingGuard.check(stagingEnv);
    if (!stagingCheck.ok) {
      print('AVISO staging: ${stagingCheck.reason}');
      print('  → testes integration/bot/hybrid ficam skip_config_missing');
    } else {
      print('Staging OK: ${stagingCheck.projectRef}');
    }

    final boot = await _bootstrapMaestro(stagingEnv);
    stagingEnv = boot.env;

    final reportDir = paths.reportDirFor(DateTime.now());
    final session = RegressionRunSession(
      guided: options.guided,
      stagingEnv: stagingEnv,
      stagingCheck: stagingCheck,
      reportDir: reportDir,
      maestroProbe: boot.probe,
      apkInstalled: boot.apkInstalled,
    );

    if (options.guided) {
      final needsLiveId = ids.any((id) => _needsLiveId(manifest[id]!));
      if (needsLiveId) {
        final liveId = await session.guidedSession.ensureLiveId(
          fromEnv: session.liveIdFromEnv,
        );
        if (liveId != null && liveId.isNotEmpty) {
          stagingEnv['LIVE_OPS_TEST_LIVE_ID'] = liveId;
          print('Guided live_id=$liveId → bots desbloqueados');
        }
      }
    } else if (session.liveIdFromEnv != null) {
      print('live_id=${session.liveIdFromEnv} → bots desbloqueados');
    }

    final executor = AdapterExecutor(paths.repoRoot, session: session);

    final coverage = computeCoverage(manifest);

    print('Fleaber Regression Runner');
    print('Comando: $command${options.guided ? " (guided)" : ""}');
    print('Adapters registados: ${coverage.total} / ${manifest.length}');
    print('  automated=${coverage.automated} manual=${coverage.manual} guided=${coverage.guided}');
    print('  overrides explícitos=${countExplicitOverrides()}');
    print('Testes seleccionados: ${ids.length} / ${manifest.length}');
    print('---');

    final sw = Stopwatch()..start();
    final results = <TestRunResult>[];

    for (final id in ids) {
      final test = manifest[id]!;
      final adapter = test.adapter;
      final dedupeKey = adapter?.dedupeKey ?? adapter?.path;

      TestRunResult result;
      if (dedupeKey != null) {
        final cached = session.cached(dedupeKey);
        if (cached != null && cached.realExecution) {
          result = TestRunResult(
            id: id,
            name: test.title,
            status: cached.status,
            layersRun: cached.layersRun,
            durationMs: 0,
            message: 'Dedupe $dedupeKey (já executado)',
          );
        } else {
          result = await executor.run(test);
          session.putCache(
            dedupeKey,
            TestRunCache(
              status: result.status,
              layersRun: result.layersRun,
              message: result.message,
              durationMs: result.durationMs,
              realExecution: result.durationMs > 0,
            ),
          );
        }
      } else {
        result = await executor.run(test);
      }

      results.add(result);
      _applyResultToState(state, id, result);
      print('${result.id} ${result.status.padRight(20)} ${test.title}');
    }

    sw.stop();
    store.saveState(state);

    final retestRequired = state.entries
        .where((e) => e.value.status == 'retest_required')
        .map((e) => e.key)
        .toList()
      ..sort();

    ReportWriter(reportDir).writeAll(
      command: command,
      gitSha: await _gitSha(),
      durationMs: sw.elapsedMilliseconds,
      results: results,
      manifest: manifest,
      retestRequired: retestRequired,
      riskSuggestions: const [],
      guided: options.guided,
      adapterCount: coverage.automated,
      coverage: coverage,
    );

    print('---');
    print('Relatório: $reportDir');
    _printSummary(results);

    final appFails =
        results.where((r) => classifyResult(r) == FailureClass.appFail).length;
    return appFails > 0 ? 1 : 0;
  }

  bool _needsLiveId(ManifestTest test) {
    final a = test.adapter;
    if (a == null) return false;
    if (a.requiresLiveId) return true;
    if (a.type == 'bot') return true;
    if (a.type == 'hybrid') return true;
    return false;
  }

  Future<({MaestroDeviceProbe probe, Map<String, String> env, bool apkInstalled})>
      _bootstrapMaestro(Map<String, String> stagingEnv) async {
    final env = Map<String, String>.from(stagingEnv);
    final maestroEnvPath = '${paths.repoRoot}/.maestro/.env';

    if (!File(maestroEnvPath).existsSync()) {
      print('A criar .maestro/.env (seller/buyer staging)…');
      final r = await Process.run(
        'dart',
        ['run', 'tool/maestro_prepare_live.dart', '--multi'],
        workingDirectory: paths.repoRoot,
        runInShell: Platform.isWindows,
      );
      if (r.exitCode != 0) {
        print('AVISO maestro_prepare_live: ${_tail(r)}');
      }
    }

    env.addAll(parseEnvFile(maestroEnvPath));

    final probe = await MaestroDeviceProbe.detect(paths.repoRoot);
    _assignMaestroDevices(env, probe.devices);

    var apkInstalled = false;
    if (probe.canRunMaestro) {
      print(
        'Maestro device OK: ${probe.devices.join(", ")} '
        '(bridge=${probe.maestroConnectedDevice}, default=${probe.defaultDevice})',
      );
      if (!probe.apkExists) {
        print('AVISO: APK debug em falta — flutter build apk --debug');
      } else {
        apkInstalled = await probe.ensureApkInstalled(
          preferDevices: [
            env['MAESTRO_DEVICE_SELLER'],
            env['MAESTRO_DEVICE_BUYER'],
            probe.defaultDevice,
          ].whereType<String>().where((d) => d.isNotEmpty).toList(),
        );
      }
      await ensureMaestroHarnessSeed(envPath: maestroEnvPath);
    } else {
      print('Maestro infra skip: ${probe.skipReason}');
    }

    return (probe: probe, env: env, apkInstalled: apkInstalled);
  }

  void _assignMaestroDevices(Map<String, String> env, List<String> devices) {
    if (devices.isEmpty) return;
    const sellerPref = 'emulator-5554';
    const buyerPref = 'emulator-5558';
    final seller = devices.contains(sellerPref)
        ? sellerPref
        : devices.first;
    final buyer = devices.contains(buyerPref)
        ? buyerPref
        : devices.length > 1
            ? devices.firstWhere((d) => d != seller, orElse: () => seller)
            : seller;
    env.putIfAbsent('MAESTRO_DEVICE_SELLER', () => seller);
    env.putIfAbsent('MAESTRO_DEVICE_BUYER', () => buyer);
    env.putIfAbsent('MAESTRO_DEVICE_DEFAULT', () => buyer);
  }

  String _tail(ProcessResult r) {
    final s = r.stderr.toString().trim();
    if (s.isNotEmpty) return s;
    return r.stdout.toString().trim();
  }

  Map<String, String>? _tryLoadStagingEnv() {
    try {
      return loadLiveOpsStagingEnv('${paths.repoRoot}/tool/live_ops_staging.env');
    } catch (_) {
      return null;
    }
  }

  String _commandLabel() {
    if (options.full) return 'full';
    if (options.failedOnly) return 'failed-only';
    if (options.retestRequired) return 'retest-required';
    if (options.range != null) return 'range:${options.range}';
    if (options.priority != null) return 'priority:${options.priority}';
    if (options.area != null) return 'area:${options.area}';
    if (options.id != null) return 'id:${options.id}';
    return 'custom';
  }

  void _applyResultToState(
    Map<String, TestState> state,
    String id,
    TestRunResult result,
  ) {
    final now = DateTime.now().toUtc().toIso8601String();
    state[id] = TestState(
      status: result.status,
      lastRun: now,
      message: result.message,
      lastDurationMs: result.durationMs,
    );
  }

  Future<int> _recordManual(String raw) async {
    final m = RegExp(r'^A(\d{3})(?:=(pass|fail|manual|skip|retest_required|blocked))?$', caseSensitive: false)
            .firstMatch(raw.replaceAll(' ', '')) ??
        RegExp(r'^A(\d{3})\s+(pass|fail|manual|skip|retest_required|blocked)$', caseSensitive: false)
            .firstMatch(raw.trim());

    if (m == null) {
      print('Formato inválido. Use: --record-manual A205=pass ou --record-manual A205 pass');
      return 2;
    }

    final id = 'A${m.group(1)!}';
    final status = (m.groupCount >= 2 ? m.group(2) : null)?.toLowerCase() ?? 'pass';

    final manifest = store.loadManifest();
    if (!manifest.containsKey(id)) {
      print('ID desconhecido: $id');
      return 1;
    }

    final state = store.loadState(manifest);
    state[id] = TestState(
      status: status,
      lastRun: DateTime.now().toUtc().toIso8601String(),
      message: 'manual record',
    );
    store.saveState(state);
    print('Registado $id → $status');
    return 0;
  }

  Future<int> _suggestRetest(String changedPath) async {
    final manifest = store.loadManifest();
    final risk = store.loadRiskGraph();
    final componentMap = risk['component_to_tests'] as Map<String, dynamic>? ?? {};
    final fixSuggests = risk['fix_suggests_retest'] as Map<String, dynamic>? ?? {};

    final normalized = _normalizeChangedPath(changedPath);
    final basename = normalized.split('/').last;

    final hitIds = <String>{};
    for (final entry in componentMap.entries) {
      final key = entry.key.toString().toLowerCase();
      if (key == normalized ||
          key.endsWith('/$basename') ||
          key == basename ||
          normalized.endsWith(key)) {
        for (final id in entry.value as List) {
          hitIds.add(id.toString());
        }
      }
    }

    final suggest = <String>{};
    for (final id in hitIds) {
      suggest.add(id);
      final edges = fixSuggests[id];
      if (edges is List) {
        for (final e in edges) {
          suggest.add(e.toString());
        }
      }
    }

    final sorted = suggest.toList()..sort();
    print('Ficheiro alterado: $changedPath');
    print('Testes directamente afectados: ${hitIds.isEmpty ? "(nenhum)" : hitIds.join(", ")}');
    print('Retest sugerido: ${sorted.isEmpty ? "(nenhum)" : sorted.join(", ")}');

    if (sorted.isNotEmpty) {
      final state = store.loadState(manifest);
      for (final id in sorted) {
        if (state.containsKey(id)) {
          state[id] = TestState(
            status: 'retest_required',
            lastRun: state[id]?.lastRun,
            message: 'risk: $basename',
          );
        }
      }
      store.saveState(state);
      print('State actualizado: ${sorted.length} testes → retest_required');
    }

    return 0;
  }

  String _normalizeChangedPath(String raw) {
    var s = raw.trim().replaceAll('\\', '/').toLowerCase();
    if (s.startsWith('lib/')) return s;
    if (s.contains('/')) return s;
    return 'lib/$s';
  }

  Future<String> _gitSha() async {
    try {
      final r = await Process.run('git', ['rev-parse', '--short', 'HEAD'],
          workingDirectory: paths.repoRoot);
      if (r.exitCode == 0) return r.stdout.toString().trim();
    } catch (_) {}
    return 'unknown';
  }

  void _printSummary(List<TestRunResult> results) {
    final counts = <String, int>{};
    for (final r in results) {
      counts[r.status] = (counts[r.status] ?? 0) + 1;
    }
    final real = results.where((r) {
      const realStatuses = {'pass', 'fail', 'flaky'};
      return realStatuses.contains(r.status) && r.durationMs > 0 || 
        (realStatuses.contains(r.status) && (r.layersRun.isNotEmpty));
    }).length;
    print('Resumo: ${counts.entries.map((e) => '${e.key}=${e.value}').join(", ")}');
    print('Execuções reais (pass/fail com layers): $real');
  }

  Future<int> _runSelfTest() async {
    var ok = true;
    void check(String name, bool cond) {
      if (!cond) {
        print('FAIL self-test: $name');
        ok = false;
      } else {
        print('OK self-test: $name');
      }
    }

    final manifest = store.loadManifest(regenerate: true);
    final coverage = computeCoverage(manifest);

    check('manifest 429 testes', manifest.length == 429);
    check('adapters registados 429', coverage.notImplemented == 0);
    check('automated >= 200', coverage.automated >= 200);
    check('overrides explícitos >= 90', countExplicitOverrides() >= 90);

    final ids = TestFilter.selectIds(
      manifest: manifest,
      state: store.loadState(manifest),
      range: 'A190-A230',
    );
    check('range A190-A230', ids.length == 41);

    final p0 = TestFilter.selectIds(
      manifest: manifest,
      state: store.loadState(manifest),
      priority: 'P0',
    );
    check('priority P0 > 0', p0.isNotEmpty);

    final checkout = TestFilter.selectIds(
      manifest: manifest,
      state: store.loadState(manifest),
      area: 'checkout',
    );
    check('area checkout > 0', checkout.isNotEmpty);

    check('area mapper A202', areaForTestId('A202') == 'checkout');
    check('A340 integration', adapterRegistry['A340']?.type == 'integration');
    check('A280 unit', adapterRegistry['A280']?.type == 'unit');

    return ok ? 0 : 1;
  }
}
