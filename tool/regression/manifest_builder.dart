// ignore_for_file: avoid_print
import 'dart:io';

import 'adapter_registry.dart';
import 'area_mapper.dart';
import 'automation_policy.dart';
import 'models.dart';

/// Gera manifest.json + risk_graph.json a partir dos docs expandidos.
class ManifestBuilder {
  ManifestBuilder(this.repoRoot);

  final String repoRoot;

  static const docFiles = [
    'live-ecosystem-test-matrix-A001-A049.md',
    'live-ecosystem-test-matrix-A050-A079.md',
    'live-ecosystem-test-matrix-A080-A129.md',
    'live-ecosystem-test-matrix-A130-A189.md',
    'live-ecosystem-test-matrix-A190-A230.md',
    'live-ecosystem-test-matrix-A231-A279.md',
    'live-ecosystem-test-matrix-A280-A349.md',
    'live-ecosystem-test-matrix-A350-A369.md',
    'live-ecosystem-test-matrix-A370-A429.md',
  ];

  Map<String, dynamic> buildManifest() {
    final tests = <String, ManifestTest>{};
    for (final doc in docFiles) {
      final path = '$repoRoot/docs/$doc';
      final file = File(path);
      if (!file.existsSync()) {
        throw StateError('Doc em falta: $path');
      }
      final content = file.readAsStringSync();
      for (final ficha in _parseFichas(content, doc)) {
        tests[ficha.id] = ficha;
      }
    }

    for (var i = 1; i <= 429; i++) {
      final id = 'A${i.toString().padLeft(3, '0')}';
      tests.putIfAbsent(
        id,
        () => ManifestTest(
          id: id,
          title: 'Reservado $id',
          area: areaForTestId(id),
          priority: 'P2',
          layer: 'not_implemented',
          status: 'not_implemented',
          sourceDoc: 'missing',
        ),
      );
    }

    final sorted = Map.fromEntries(
      tests.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );

    final resolved = applyRegistryToManifest(sorted);

    return {
      'version': 1,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'source': 'docs/live-ecosystem-test-matrix-A*.md',
      'automation_policy': {
        'manual_checkpoint_ids': kManualCheckpointIds.toList()..sort(),
        'guided_checkpoint_ids': kGuidedCheckpointIds.toList()..sort(),
        'expected_automated': kExpectedAutomated,
      },
      'tests': resolved.map((k, v) => MapEntry(k, v.toJson())),
    };
  }

  Map<String, dynamic> buildRiskGraph(Map<String, ManifestTest> tests) {
    final componentToTests = <String, List<String>>{};
    final fixSuggests = <String, List<String>>{};

    for (final t in tests.values) {
      for (final c in t.components) {
        final key = _normalizeComponent(c);
        if (key.isEmpty) continue;
        componentToTests.putIfAbsent(key, () => []).add(t.id);
      }
      if (t.riskEdges.isNotEmpty) {
        fixSuggests[t.id] = List<String>.from(t.riskEdges);
      }
      for (final dep in t.dependencies) {
        fixSuggests.putIfAbsent(dep, () => []);
        if (!fixSuggests[dep]!.contains(t.id)) {
          fixSuggests[dep]!.add(t.id);
        }
      }
    }

    for (final list in componentToTests.values) {
      list.sort();
    }
    for (final list in fixSuggests.values) {
      list.sort();
    }

    return {
      'version': 1,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'component_to_tests': componentToTests,
      'fix_suggests_retest': fixSuggests,
    };
  }

  List<ManifestTest> _parseFichas(String content, String sourceDoc) {
    final out = <ManifestTest>[];
    final headerRe = RegExp(r'^## (A\d{3})\s+[—–\-]\s+', multiLine: true);
    final matches = headerRe.allMatches(content).toList();
    if (matches.isEmpty) return out;

    for (var i = 0; i < matches.length; i++) {
      final id = matches[i].group(1)!.trim();
      final start = matches[i].end;
      final end = i + 1 < matches.length ? matches[i + 1].start : content.length;
      final body = content.substring(start, end);
      final fields = _parseTableFields(body);
      if (fields.isEmpty) continue;

      final title = fields['nome'] ?? fields['name'] ?? id;
      final priority = _normalizePriority(fields['prioridade'] ?? 'P2');
      final layer = _layerFromTipo(fields['tipo recomendado'] ?? '');
      final components = _extractComponents(fields['componentes afectados'] ?? '');
      final dependencies = _extractIds(fields['dependências'] ?? fields['dependencias'] ?? '');
      final adapter = adapterRegistry[id];
      final automatizable = (fields['automatizável'] ?? fields['automatizavel'] ?? '')
          .toLowerCase();

      String status;
      RegressionAdapter? adapterObj;
      if (adapter != null) {
        adapterObj = adapter;
        status = 'automated';
      } else if (layer == 'manual' ||
          automatizable == 'não' ||
          automatizable == 'nao' ||
          automatizable == 'no') {
        status = 'manual';
      } else if (layer == 'not_implemented') {
        status = 'not_implemented';
      } else {
        status = 'not_implemented';
      }

      out.add(
        ManifestTest(
          id: id,
          title: title,
          area: areaForTestId(id),
          priority: priority,
          layer: adapter != null ? adapter.type : layer,
          status: status,
          adapter: adapterObj,
          dependencies: dependencies,
          riskEdges: const [],
          sourceDoc: sourceDoc,
          components: components,
        ),
      );
    }
    return out;
  }

  Map<String, String> _parseTableFields(String body) {
    final fields = <String, String>{};
    final rowRe = RegExp(
      r'^\|\s*\*\*([^*]+)\*\*\s*\|\s*(.+?)\s*\|\s*$',
      multiLine: true,
    );
    for (final m in rowRe.allMatches(body)) {
      final key = m.group(1)!.trim().toLowerCase();
      var val = m.group(2)!.trim();
      if (val == '—' || val == '-') val = '';
      fields[key] = val;
    }
    return fields;
  }

  String _normalizePriority(String raw) {
    final m = RegExp(r'P[0-3]').firstMatch(raw.toUpperCase());
    return m?.group(0) ?? 'P2';
  }

  String _layerFromTipo(String tipo) {
    final t = tipo.toLowerCase();
    if (t.isEmpty || t.contains('n/a')) return 'not_implemented';
    if (t.contains('unit')) return 'unit';
    if (t.contains('integration')) return 'integration';
    if (t.contains('bot')) return 'bot';
    if (t.contains('maestro')) return 'maestro';
    if (t.contains('manual')) return 'manual';
    if (t.contains('híbrido') || t.contains('hibrido') || t.contains('hybrid')) {
      return 'hybrid';
    }
    if (t.contains('h01') || t.contains('h07')) return 'hybrid';
    return 'not_implemented';
  }

  List<String> _extractIds(String raw) {
    if (raw.isEmpty) return const [];
    return RegExp(r'A\d{3}')
        .allMatches(raw)
        .map((m) => m.group(0)!)
        .toSet()
        .toList()
      ..sort();
  }

  List<String> _extractComponents(String raw) {
    if (raw.isEmpty) return const [];
    final out = <String>{};
    for (final m in RegExp(r'[\w./\\-]+\.dart').allMatches(raw)) {
      out.add(m.group(0)!);
    }
    for (final m in RegExp(r'`([^`]+)`').allMatches(raw)) {
      final g = m.group(1)!;
      if (g.contains('.dart') || g.contains('/') || g.contains('.')) {
        out.add(g);
      }
    }
    return out.toList()..sort();
  }

  String _normalizeComponent(String raw) {
    var s = raw.trim().toLowerCase().replaceAll('\\', '/');
    if (s.startsWith('lib/')) return s;
    if (s.contains('/')) return s;
    if (s.endsWith('.dart')) return 'lib/$s';
    return s;
  }
}
