// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'adapter_registry.dart';
import 'manifest_builder.dart';
import 'models.dart';

class RegressionPaths {
  RegressionPaths(this.repoRoot);

  final String repoRoot;

  String get manifestPath => '$repoRoot/test/regression/manifest.json';
  String get statePath => '$repoRoot/test/regression/state.json';
  String get riskGraphPath => '$repoRoot/test/regression/risk_graph.json';

  String reportDirFor(DateTime now) {
    final stamp = now.toUtc().toIso8601String().replaceAll(':', '-').split('.').first;
    return '$repoRoot/tool/reports/regression_$stamp';
  }
}

class RegressionStore {
  RegressionStore(this.paths);

  final RegressionPaths paths;

  Map<String, ManifestTest> loadManifest({bool regenerate = false}) {
    final file = File(paths.manifestPath);
    if (regenerate || !file.existsSync()) {
      _writeManifestFromDocs();
    }
    final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final testsRaw = raw['tests'] as Map<String, dynamic>? ?? {};
    return testsRaw.map(
      (k, v) => MapEntry(
        k,
        applyAdapterRegistry(
          ManifestTest.fromJson({...v as Map<String, dynamic>, 'id': k}),
        ),
      ),
    );
  }

  Map<String, dynamic> loadRiskGraph({bool regenerate = false}) {
    final file = File(paths.riskGraphPath);
    if (regenerate || !file.existsSync()) {
      _writeManifestFromDocs();
    }
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  Map<String, TestState> loadState(Map<String, ManifestTest> manifest) {
    final file = File(paths.statePath);
    if (!file.existsSync()) {
      return _defaultState(manifest);
    }
    final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final testsRaw = raw['tests'] as Map<String, dynamic>? ?? {};
    final out = <String, TestState>{};
    for (final id in manifest.keys) {
      final entry = testsRaw[id];
      out[id] = entry is Map<String, dynamic>
          ? TestState.fromJson(entry)
          : TestState(status: manifest[id]!.status);
    }
    return out;
  }

  void saveState(Map<String, TestState> state) {
    final file = File(paths.statePath);
    file.parent.createSync(recursive: true);
    final payload = {
      'version': 1,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'tests': state.map((k, v) => MapEntry(k, v.toJson())),
    };
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
  }

  void _writeManifestFromDocs() {
    final builder = ManifestBuilder(paths.repoRoot);
    final manifestPayload = builder.buildManifest();
    final tests = manifestPayload['tests'] as Map<String, dynamic>;
    final parsed = tests.map(
      (k, v) => MapEntry(k, ManifestTest.fromJson({...v as Map<String, dynamic>, 'id': k})),
    );

    final manifestFile = File(paths.manifestPath);
    manifestFile.parent.createSync(recursive: true);
    manifestFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(manifestPayload),
    );

    final risk = builder.buildRiskGraph(parsed);
    File(paths.riskGraphPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(risk),
    );
  }

  Map<String, TestState> _defaultState(Map<String, ManifestTest> manifest) {
    return manifest.map(
      (k, v) => MapEntry(k, TestState(status: v.status)),
    );
  }
}
