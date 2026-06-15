// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'adapter_auto_mapper.dart';
import 'area_mapper.dart';
import 'failure_classifier.dart';
import 'models.dart';

class ReportWriter {
  ReportWriter(this.reportDir);

  final String reportDir;

  void writeAll({
    required String command,
    required String gitSha,
    required int durationMs,
    required List<TestRunResult> results,
    required Map<String, ManifestTest> manifest,
    required List<String> retestRequired,
    required List<String> riskSuggestions,
    bool guided = false,
    int adapterCount = 0,
    AdapterCoverageStats? coverage,
  }) {
    Directory(reportDir).createSync(recursive: true);

    final summary = _countStatuses(results);
    final payload = {
      'run_id': reportDir.split(Platform.pathSeparator).last,
      'command': command,
      'guided': guided,
      'git_sha': gitSha,
      'environment': 'staging_guarded',
      'adapter_count': adapterCount,
      'duration_ms': durationMs,
      'summary': summary,
      'tests': results.map((r) => r.toJson()).toList(),
    };

    _write('results.json', const JsonEncoder.withIndent('  ').convert(payload));
    _write('summary.md', _summaryMd(command, gitSha, durationMs, summary, results, guided: guided, adapterCount: adapterCount));
    _write('failed.md', _failedMd(results));
    _write('retest_required.md', _retestMd(retestRequired, riskSuggestions));
    _write('coverage_by_area.md', _coverageMd(results, manifest));
    _write('regression_risk.md', _riskMd(riskSuggestions, retestRequired));
    _write('executed_real_tests.md', _executedRealMd(results, manifest));
    _write('skipped_with_reason.md', _skippedMd(results));
    _write('manual_required.md', _manualRequiredMd(results));
    _write('bot_maestro_results.md', _botMaestroMd(results));
    _write('app_failures.md', _classifiedMd(results, FailureClass.appFail));
    _write('infra_failures.md', _classifiedMd(results, FailureClass.infraFail));
    _write('manual_checkpoints.md', _classifiedMd(results, FailureClass.manualCheckpoint));
    _write('guided_checkpoints.md', _classifiedMd(results, FailureClass.guidedCheckpoint));
    _write('failure_classification.md', _classificationSummaryMd(results));
    if (coverage != null) {
      _write('p0_gaps.md', _p0GapsMd(coverage));
      _write('top_20_next.md', _top20NextMd(manifest, results));
    }
  }

  void _write(String name, String content) {
    File('$reportDir${Platform.pathSeparator}$name').writeAsStringSync(content);
  }

  Map<String, int> _countStatuses(List<TestRunResult> results) {
    final c = <String, int>{
      'pass': 0,
      'fail': 0,
      'skip': 0,
      'skip_config_missing': 0,
      'manual': 0,
      'not_implemented': 0,
      'flaky': 0,
      'retest_required': 0,
      'blocked': 0,
    };
    for (final r in results) {
      c[r.status] = (c[r.status] ?? 0) + 1;
    }
    return c;
  }

  String _summaryMd(
    String command,
    String gitSha,
    int durationMs,
    Map<String, int> summary,
    List<TestRunResult> results, {
    bool guided = false,
    int adapterCount = 0,
  }) {
    final buf = StringBuffer()
      ..writeln('# Fleaber Regression — summary')
      ..writeln()
      ..writeln('| Campo | Valor |')
      ..writeln('|-------|-------|')
      ..writeln('| Comando | `$command` |')
      ..writeln('| Guided | $guided |')
      ..writeln('| Adapters reais | $adapterCount |')
      ..writeln('| Git SHA | `$gitSha` |')
      ..writeln('| Duração | ${durationMs}ms |')
      ..writeln('| Total | ${results.length} |')
      ..writeln()
      ..writeln('## Contagens')
      ..writeln()
      ..writeln('| Status | N |')
      ..writeln('|--------|---|');
    for (final e in summary.entries) {
      if (e.value > 0) buf.writeln('| ${e.key} | ${e.value} |');
    }
    final fails = results.where((r) => r.status == 'fail').toList();
    if (fails.isNotEmpty) {
      buf.writeln();
      buf.writeln('## FAIL');
      buf.writeln();
      for (final f in fails) {
        buf.writeln('- **${f.id}** ${f.name}: ${f.message ?? "(sem mensagem)"}');
      }
    }
    final manuals = results.where((r) => r.status == 'manual').take(20).toList();
    if (manuals.isNotEmpty) {
      buf.writeln();
      buf.writeln('## MANUAL (primeiros 20)');
      buf.writeln();
      for (final m in manuals) {
        buf.writeln('- **${m.id}** ${m.name}');
      }
    }
    buf.writeln();
    buf.writeln('## Próximo passo');
    buf.writeln();
    buf.writeln('- `dart run tool/fleaber_regression_runner.dart --failed-only`');
    buf.writeln('- `dart run tool/fleaber_regression_runner.dart --retest-required`');
    return buf.toString();
  }

  String _executedRealMd(List<TestRunResult> results, Map<String, ManifestTest> manifest) {
    final real = results.where((r) {
      if (r.status != 'pass' && r.status != 'fail') return false;
      return r.layersRun.isNotEmpty;
    }).toList();
    final buf = StringBuffer('# executed_real_tests\n\n');
    buf.writeln('Total: ${real.length}\n');
    for (final r in real) {
      final layer = manifest[r.id]?.adapter?.type ?? r.layersRun.join('+');
      buf.writeln('- **${r.id}** [`$layer`] ${r.status} — ${r.name}');
    }
    return buf.toString();
  }

  String _skippedMd(List<TestRunResult> results) {
    final skipped = results
        .where((r) => r.status == 'skip_config_missing' || r.status == 'skip')
        .toList();
    if (skipped.isEmpty) return '# skipped_with_reason\n\nNenhum skip.\n';
    final buf = StringBuffer('# skipped_with_reason\n\n');
    for (final s in skipped) {
      buf.writeln('- **${s.id}** ${s.name}: ${s.message ?? "—"}');
    }
    return buf.toString();
  }

  String _manualRequiredMd(List<TestRunResult> results) {
    final manual = results.where((r) => r.status == 'manual' || r.status == 'blocked').toList();
    if (manual.isEmpty) return '# manual_required\n\nNada pendente.\n';
    final buf = StringBuffer('# manual_required\n\n');
    for (final m in manual) {
      buf.writeln('- **${m.id}** [${m.status}] ${m.name}');
      if (m.message != null) buf.writeln('  - ${m.message}');
    }
    return buf.toString();
  }

  String _classifiedMd(List<TestRunResult> results, FailureClass cls) {
    final title = failureClassLabel(cls);
    final items =
        results.where((r) => classifyResult(r) == cls).toList();
    if (items.isEmpty) return '# $title\n\nNenhum.\n';
    final buf = StringBuffer('# $title\n\nTotal: ${items.length}\n\n');
    for (final r in items) {
      buf.writeln('- **${r.id}** [${r.status}] ${r.name}');
      if (r.message != null) buf.writeln('  - ${r.message}');
    }
    return buf.toString();
  }

  String _classificationSummaryMd(List<TestRunResult> results) {
    final counts = <FailureClass, int>{};
    for (final r in results) {
      final c = classifyResult(r);
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final buf = StringBuffer('# failure_classification\n\n')
      ..writeln('| Classe | N |')
      ..writeln('|--------|---|');
    for (final c in FailureClass.values) {
      final n = counts[c] ?? 0;
      if (n > 0) buf.writeln('| ${failureClassLabel(c)} | $n |');
    }
    buf.writeln();
    buf.writeln('## Legenda');
    buf.writeln('- **app_fail**: falha real da app (assert/flow)');
    buf.writeln('- **infra_fail**: device, adb, dedupe, config em falta');
    buf.writeln('- **manual_checkpoint**: validação humana documentada');
    buf.writeln('- **guided_checkpoint**: requer `--guided` interactivo');
    return buf.toString();
  }

  String _botMaestroMd(List<TestRunResult> results) {
    final layers = results.where((r) {
      return r.layersRun.any((l) => l == 'bot' || l == 'maestro' || l == 'hybrid');
    }).toList();
    final buf = StringBuffer('# bot_maestro_results\n\n');
    if (layers.isEmpty) {
      buf.writeln('Nenhum teste bot/maestro/hybrid nesta execução.\n');
      return buf.toString();
    }
    for (final r in layers) {
      buf.writeln('- **${r.id}** ${r.status} layers=${r.layersRun.join(",")} — ${r.message ?? r.name}');
    }
    return buf.toString();
  }

  String _p0GapsMd(AdapterCoverageStats coverage) {
    final buf = StringBuffer('# p0_gaps\n\n');
    buf.writeln('| Métrica | Valor |');
    buf.writeln('|---------|-------|');
    buf.writeln('| P0 total | ${coverage.p0Total} |');
    buf.writeln('| P0 automated | ${coverage.p0Automated} |');
    buf.writeln('| P0 gaps | ${coverage.p0Gaps.length} |');
    buf.writeln();
    if (coverage.p0Gaps.isEmpty) {
      buf.writeln('Todos os P0 têm adapter automated.\n');
    } else {
      buf.writeln('## P0 não cobertos por automação\n');
      for (final g in coverage.p0Gaps.take(50)) {
        buf.writeln('- $g');
      }
    }
    return buf.toString();
  }

  String _top20NextMd(
    Map<String, ManifestTest> manifest,
    List<TestRunResult> results,
  ) {
    final candidates = manifest.values.where((t) {
      final a = t.adapter;
      if (a == null) return true;
      return a.type == 'manual_checkpoint' ||
          a.type == 'unit' && t.priority == 'P0';
    }).toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    final buf = StringBuffer('# top_20_next\n\n');
    buf.writeln('Próximos candidatos a automação real:\n');
    for (final t in candidates.take(20)) {
      final a = t.adapter;
      buf.writeln('- **${t.id}** [${a?.type ?? "none"}] P${t.priority.replaceFirst("P", "")} — ${t.title}');
    }
    return buf.toString();
  }

  String _failedMd(List<TestRunResult> results) {
    final fails = results.where((r) => r.status == 'fail' || r.status == 'flaky').toList();
    if (fails.isEmpty) return '# failed\n\nNenhum FAIL nesta execução.\n';
    final buf = StringBuffer('# failed\n\n');
    for (final f in fails) {
      buf.writeln('## ${f.id} — ${f.name}\n');
      buf.writeln('- Status: `${f.status}`');
      buf.writeln('- Layers: ${f.layersRun.join(", ")}');
      buf.writeln('- Mensagem: ${f.message ?? "—"}\n');
    }
    return buf.toString();
  }

  String _retestMd(List<String> required, List<String> suggested) {
    final buf = StringBuffer('# retest_required\n\n');
    if (required.isNotEmpty) {
      buf.writeln('## Estado retest_required\n');
      buf.writeln(required.join(', '));
      buf.writeln();
    }
    if (suggested.isNotEmpty) {
      buf.writeln('## Sugestões risk-based\n');
      buf.writeln(suggested.join(', '));
      buf.writeln();
    }
    if (required.isEmpty && suggested.isEmpty) {
      buf.writeln('Nada pendente.\n');
    }
    return buf.toString();
  }

  String _coverageMd(
    List<TestRunResult> results,
    Map<String, ManifestTest> manifest,
  ) {
    final byArea = <String, List<TestRunResult>>{};
    for (final r in results) {
      final area = manifest[r.id]?.area ?? 'unknown';
      byArea.putIfAbsent(area, () => []).add(r);
    }
    final buf = StringBuffer('# coverage_by_area\n\n')
      ..writeln('| Área | Total | pass | fail | manual | not_impl |')
      ..writeln('|------|-------|------|------|--------|----------|');
    for (final area in byArea.keys.toList()..sort()) {
      final list = byArea[area]!;
      int pass = 0, fail = 0, manual = 0, ni = 0;
      for (final r in list) {
        switch (r.status) {
          case 'pass':
            pass++;
            break;
          case 'fail':
            fail++;
            break;
          case 'manual':
            manual++;
            break;
          case 'not_implemented':
            ni++;
            break;
        }
      }
      buf.writeln('| $area | ${list.length} | $pass | $fail | $manual | $ni |');
    }
    return buf.toString();
  }

  String _riskMd(List<String> suggested, List<String> required) {
    return '# regression_risk\n\n'
        'Sugestões desta execução/sessão:\n\n'
        '${suggested.isEmpty ? "(nenhuma)\n" : suggested.join(", ") + "\n"}\n'
        'Marcados retest_required no state:\n\n'
        '${required.isEmpty ? "(nenhum)\n" : required.join(", ") + "\n"}';
  }
}

class TestFilter {
  static List<String> selectIds({
    required Map<String, ManifestTest> manifest,
    required Map<String, TestState> state,
    String? range,
    String? priority,
    String? area,
    String? singleId,
    bool failedOnly = false,
    bool retestRequired = false,
  }) {
    Iterable<String> ids = manifest.keys;

    if (singleId != null) {
      return manifest.containsKey(singleId) ? [singleId] : [];
    }

    if (range != null) {
      final m = RegExp(r'^A(\d{3})-A(\d{3})$', caseSensitive: false).firstMatch(range.trim());
      if (m != null) {
        final lo = int.parse(m.group(1)!);
        final hi = int.parse(m.group(2)!);
        ids = ids.where((id) {
          if (!RegExp(r'^A\d{3}$').hasMatch(id)) return false;
          final n = int.parse(id.substring(1));
          return n >= lo && n <= hi;
        });
      }
    }

    if (priority != null) {
      final p = priority.toUpperCase().startsWith('P') ? priority.toUpperCase() : 'P$priority';
      ids = ids.where((id) => manifest[id]!.priority == p);
    }

    if (area != null) {
      ids = ids.where((id) => areaMatchesFilter(manifest[id]!.area, area));
    }

    if (failedOnly) {
      ids = ids.where((id) {
        final s = state[id]?.status ?? manifest[id]!.status;
        return s == 'fail' || s == 'flaky';
      });
    }

    if (retestRequired) {
      ids = ids.where((id) {
        final s = state[id]?.status ?? '';
        return s == 'retest_required';
      });
    }

    final list = ids.toList()..sort();
    return list;
  }
}
